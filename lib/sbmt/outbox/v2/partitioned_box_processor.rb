# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool"

module Sbmt
  module Outbox
    module V2
      class PartitionedBoxProcessor
        delegate :alive?, to: :thread_pool
        delegate logger, to: "Sbmt::Outbox"

        Task = Struct.new(
          :item_class,
          :partition,
          :buckets,
          :resource_key,
          :resource_path,
          keyword_init: true
        ) do
          def log_tags
            {
              box_type: item_class.box_type,
              box_name: item_class.box_name,
              box_partition: partition
            }
          end
        end

        def initialize(boxes:, partitions_count:, threads_count:, name: "abstract_worker", throttler: nil)
          @queue = build_task_queue(boxes)
          @partitions_count = partitions_count
          @worker_name = name
          @thread_pool = ThreadPool.new(
            concurrency: threads_count,
            name: "#{name}_thread_pool",
            throttler: throttler
          ) do
            queue.pop
          end
          @started = false
        end

        def start
          raise "#{worker_name} is already started" if started
          self.started = true

          thread_pool.start do |worker_number, task|
            result = ThreadPool::PROCESSED

            logger.with_tags(**task.log_tags) do
              result = safe_process_task(worker_number, task)
            end

            result
          ensure
            queue << task
          end
        rescue => e
          Outbox.error_tracker.error(e)
          raise
        ensure
          self.started = false
        end

        def ready?
          started
        end

        def alive?(timeout)
          return false unless started

          @thread_pool.alive?(timeout)
        end

        def safe_process_task(worker_number, task)
          process_task(worker_number, task)
        rescue => e
          log_fatal(e, task, worker_number)
          track_fatal(e, task, worker_number)
        end

        def process_task(_worker_number, _task)
          raise NotImplementedError, "Implement #process_task for Sbmt::Outbox::V2::PartitionedBoxProcessor"
        end

        private

        attr_accessor :queue, :started, :thread_pool, :partitions_count, :worker_name

        def build_task_queue(boxes)
          res = boxes.map do |item_class|
            schedule_concurrency = (0...partitions_count).to_a
            schedule_concurrency.map do |partition|
              buckets = item_class.calc_bucket_partitions(partition).fetch(partition)
              resource_key = "#{item_class.box_name}:#{partition}"

              Task.new(
                item_class: item_class,
                partition: partition,
                buckets: buckets,
                resource_key: resource_key,
                resource_path: "sbmt:outbox:#{worker_name}:#{resource_key}"
              )
            end
          end.flatten

          res.shuffle!

          Queue.new(res)
        end

        def log_fatal(e, task, worker_number)
          backtrace = e.backtrace.join("\n") if e.respond_to?(:backtrace)

          logger.log_error(
            "Failed processing #{task.resource_key} with error: #{e.class} #{e.message}",
            backtrace: backtrace
          )
        end

        def track_fatal(e, task, worker_number)
          Outbox.error_tracker.error(e, **task.log_tags)
        end
      end
    end
  end
end
