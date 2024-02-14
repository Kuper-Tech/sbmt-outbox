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
            threads_count: 1, name: "poller"
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
          Outbox.database_switcher.use_slave do
            item_class = task.item_class
            ids_per_bucket = item_class
              .for_processing
              .where(bucket: task.buckets)
              .order(id: :asc)
              .limit(poller_config.batch_size)
              .pluck(:bucket, :id)
              # hash: bucket => [id1, id2, id3] (with preserved ids order)
              .group_by { |bucket, _| bucket }
              .transform_values { |pairs| pairs.map { |_, id| id } }

            push_to_redis(item_class, ids_per_bucket) if ids.present?
          end
        end

        def push_to_redis(item_class, ids_per_bucket)
          ids_per_bucket.each do |bucket, ids|
            redis_job = RedisJob.new(item_class.name, bucket, ids)
            redis.call("LPUSH", "#{item_class.name}:job_queue", redis_job.serialize)
          end
        end

        def poller_config
          worker_config_v2.poller
        end
      end
    end
  end
end
