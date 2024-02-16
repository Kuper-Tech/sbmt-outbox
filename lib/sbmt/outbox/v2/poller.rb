# frozen_string_literal: true

require "redlock"
require "sbmt/outbox/v2/partitioned_box_processor"
require "sbmt/outbox/v2/redis_job"

module Sbmt
  module Outbox
    module V2
      class Poller < PartitionedBoxProcessor
        delegate :worker_config_v2, :logger, to: "Sbmt::Outbox"
        attr_reader :partitions_count, :threads_count, :lock_timeout, :regular_items_batch_size, :retryable_items_batch_size

        def initialize(
          boxes,
          partitions_count: worker_config_v2.poller.concurrency,
          threads_count: worker_config_v2.poller.threads_count,
          lock_timeout: worker_config_v2.poller.general_timeout,
          regular_items_batch_size: worker_config_v2.poller.regular_items_batch_size,
          retryable_items_batch_size: worker_config_v2.poller.retryable_items_batch_size
        )
          super(
            boxes: boxes,
            partitions_count: partitions_count,
            threads_count: threads_count,
            lock_timeout: lock_timeout,
            name: "poller"
          )
          @regular_items_batch_size = regular_items_batch_size
          @retryable_items_batch_size = retryable_items_batch_size
        end

        def process_task(_worker_number, task)
          poll(task)
        end

        private

        def poll(task)
          lock_timer = Cutoff.new(lock_timeout)
          last_id = 0

          Outbox.database_switcher.use_slave do
            item_class = task.item_class

            result = fetch_items(item_class, task.buckets) do |item|
              last_id = item.id
              lock_timer.checkpoint!
            end

            push_to_redis(item_class, result) if result.present?
          end
        rescue Cutoff::CutoffExceededError
          logger.log_info("Lock timeout while processing #{task.resource_key} at id #{last_id}")
        end

        def fetch_items(item_class, buckets)
          scope = item_class
            .for_processing
            .where(bucket: buckets)
            .select(:id, :bucket, :processed_at)

          regular_count = 0
          retryable_count = 0

          # single buffer to preserve item's positions
          poll_buffer = {}

          scope.find_each(batch_size: regular_items_batch_size) do |item|
            if item.processed_at
              # skip if retryable buffer capacity limit reached
              next if retryable_count >= retryable_items_batch_size

              poll_buffer[item.bucket] ||= []
              poll_buffer[item.bucket] << item.id

              retryable_count += 1
            else
              poll_buffer[item.bucket] ||= []
              poll_buffer[item.bucket] << item.id

              regular_count += 1
            end

            # regular items have priority over retryable ones
            break if regular_count >= regular_items_batch_size

            yield(item)
          end

          poll_buffer
        end

        def push_to_redis(item_class, ids_per_bucket)
          redis.pipelined do |conn|
            ids_per_bucket.each do |bucket, ids|
              redis_job = RedisJob.new(bucket, ids)
              conn.call("LPUSH", "#{item_class.box_name}:job_queue", redis_job.serialize)
            end
          end
        end
      end
    end
  end
end
