# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool"

module Sbmt
  module Outbox
    module V2
      class PartitionedBoxProcessor
        delegate :alive?, to: :thread_pool

        Task = Struct.new(
          :item_class,
          :partition,
          :buckets,
          :resource_key,
          :resource_path,
          keyword_init: true
        )

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

            logger.with_tags(
              box_type: task.item_class.box_type,
              box_name: task.item_class.box_name,
              box_partition: task.partition
            ) do
              result = process_task(worker_number, task)
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
          started && thread_workers.any?
        end

        def alive?
          return false unless started

          deadline = Time.current - general_timeout
          thread_workers.all? do |_worker_number, time|
            deadline < time
          end
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
      end
    end
  end
end
