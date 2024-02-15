# frozen_string_literal: true

require "redlock"
require "sbmt/outbox/v2/partitioned_box_processor"
require "sbmt/outbox/v2/redis_job"

module Sbmt
  module Outbox
    module V2
      class Poller < PartitionedBoxProcessor
        delegate :worker_config_v2, :logger, to: "Sbmt::Outbox"

        def initialize(boxes)
          super(
            boxes: boxes, partitions_count: poller_config.concurrency,
            threads_count: poller_config.threads_count, name: "poller"
          )
          init_redis
        end

        def init_redis
          self.redis = ConnectionPool::Wrapper.new(size: concurrency) { RedisClientFactory.build(config.redis) }

          client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
            redis
          else
            ConnectionPool::Wrapper.new(size: concurrency) { Redis.new(config.redis) }
          end

          self.lock_manager = Redlock::Client.new([client], retry_count: 0)
        end

        def process_task(_worker_number, task)
          result = ThreadPool::PROCESSED

          lock_manager.lock("#{task.resource_path}:lock", poller_config.general_timeout * 1000) do |locked|
            if locked
              ::Rails.application.executor.wrap do
                poll(task)
              end
            else
              result = ThreadPool::SKIPPED
            end
          end

          result
        end

        private

        def poll(task)
          lock_timer = Cutoff.new(general_timeout)
          last_id = 0

          Outbox.database_switcher.use_slave do
            item_class = job.item_class

            scope = item_class
              .for_processing
              .where(bucket: task.buckets)
              .select(:id, :bucket, :processed_at)

            regular_count = 0
            retryable_count = 0

            # single buffer to preserve item's positions
            poll_buffer = {}

            scope.find_each(batch_size: poller_config.regular_items_batch_size) do |item|
              last_id = item.id

              if item.processed_at
                # skip if retryable buffer capacity limit reached
                next if retryable_count >= poller_config.retryable_items_batch_size

                poll_buffer[item.bucket] ||= []
                poll_buffer[item.bucket] << item.id

                retryable_count += 1
              else
                poll_buffer[item.bucket] ||= []
                poll_buffer[item.bucket] << item.id

                regular_count += 1
              end

              lock_timer.checkpoint!

              # regular items have priority over retryable ones
              break if regular_count >= poller_config.regular_items_batch_size
            end

            push_to_redis(item_class, poll_buffer) if poll_buffer.present?
          end
        rescue Cutoff::CutoffExceededError
          logger.log_info("Lock timeout while processing #{task.resource_key} at id #{last_id}")
        end

        def push_to_redis(item_class, ids_per_bucket)
          redis.pipelined do |conn|
            ids_per_bucket.each do |bucket, ids|
              redis_job = RedisJob.new(item_class.name, bucket, ids)
              conn.call("LPUSH", "#{item_class.name}:job_queue", redis_job.serialize)
            end
          end
        end

        def poller_config
          worker_config_v2.poller
        end
      end
    end
  end
end
