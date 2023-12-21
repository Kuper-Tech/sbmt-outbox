# frozen_string_literal: true

require "redlock"
require "sbmt/outbox/thread_pool"

module Sbmt
  module Outbox
    class Worker
      Job = Struct.new(
        :item_class,
        :partition,
        :buckets,
        :log_tags,
        :yabeda_labels,
        :resource_key,
        :resource_path,
        keyword_init: true
      )

      delegate :config,
        :logger,
        :batch_process_middlewares,
        :item_process_middlewares,
        to: "Sbmt::Outbox"
      delegate :stop, to: :thread_pool
      delegate :general_timeout, :cutoff_timeout, :batch_size, to: "Sbmt::Outbox.config.process_items"
      delegate :job_counter,
        :job_execution_runtime,
        :item_execution_runtime,
        :job_items_counter,
        :job_timeout_counter,
        to: "Yabeda.box_worker"

      def initialize(boxes:, concurrency: 10)
        self.queue = Queue.new
        build_jobs(boxes).each { |job| queue << job }
        self.thread_pool = ThreadPool.new { queue.pop }
        self.concurrency = [concurrency, queue.size].min
        self.thread_workers = {}
        init_redis
      end

      def start
        raise "Outbox is already started" if started
        self.started = true
        self.thread_workers = {}

        thread_pool.start(concurrency: concurrency) do |worker_number, job|
          touch_thread_worker!
          result = ThreadPool::PROCESSED
          logger.with_tags(**job.log_tags.merge(worker: worker_number)) do
            lock_manager.lock("#{job.resource_path}:lock", general_timeout * 1000) do |locked|
              labels = job.yabeda_labels.merge(worker_number: worker_number)

              if locked
                job_execution_runtime.measure(labels) do
                  ::Rails.application.executor.wrap do
                    safe_process_job(job, worker_number, labels)
                  end
                end
              else
                result = ThreadPool::SKIPPED
                logger.log_info("Skip processing already locked #{job.resource_key}")
              end

              job_counter.increment(labels.merge(state: locked ? "processed" : "skipped"), by: 1)
            end
          end

          result
        ensure
          queue << job
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

      private

      attr_accessor :queue, :thread_pool, :concurrency, :lock_manager, :redis, :thread_workers, :started

      def init_redis
        self.redis = ConnectionPool::Wrapper.new(size: concurrency) { RedisClientFactory.build(config.redis) }

        client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
          redis
        else
          ConnectionPool::Wrapper.new(size: concurrency) { Redis.new(config.redis) }
        end

        self.lock_manager = Redlock::Client.new([client], retry_count: 0)
      end

      def build_jobs(boxes)
        res = boxes.map do |item_class|
          partitions = (0...item_class.config.partition_size).to_a
          partitions.map do |partition|
            buckets = item_class.partition_buckets.fetch(partition)
            resource_key = "#{item_class.box_name}/#{partition}:{#{buckets.join(",")}}"

            Job.new(
              item_class: item_class,
              partition: partition,
              buckets: buckets,
              log_tags: {
                box_type: item_class.box_type,
                box_name: item_class.box_name,
                box_partition: partition,
                trace_id: nil
              },
              yabeda_labels: {
                type: item_class.box_type,
                name: item_class.box_name,
                partition: partition
              },
              resource_key: resource_key,
              resource_path: "sbmt/outbox/worker/#{resource_key}"
            )
          end
        end.flatten

        res.shuffle! if Outbox.config.worker.shuffle_jobs
        res
      end

      def touch_thread_worker!
        thread_workers[thread_pool.worker_number] = Time.current
      end

      def safe_process_job(job, worker_number, labels)
        middlewares = Middleware::Builder.new(batch_process_middlewares)

        middlewares.call(job) do
          start_id ||= redis.call("GETDEL", "#{job.resource_path}:last_id").to_i + 1
          logger.log_info("Start processing #{job.resource_key} from id #{start_id}")
          process_job_with_timeouts(job, start_id, labels)
        end
      rescue => e
        log_fatal(e, job, worker_number)
        track_fatal(e, job, worker_number)
      end

      def process_job_with_timeouts(job, start_id, labels)
        count = 0
        last_id = nil
        lock_timer = Cutoff.new(general_timeout)
        requeue_timer = Cutoff.new(cutoff_timeout)

        process_job(job, start_id, labels) do |item|
          job_items_counter.increment(labels, by: 1)
          last_id = item.id
          count += 1
          lock_timer.checkpoint!
          requeue_timer.checkpoint!
        end

        logger.log_info("Finish processing #{job.resource_key} at id #{last_id}")
      rescue Cutoff::CutoffExceededError
        job_timeout_counter.increment(labels, by: 1)

        msg = if lock_timer.exceeded?
          "Lock timeout"
        elsif requeue_timer.exceeded?
          redis.call("SET", "#{job.resource_path}:last_id", last_id, "EX", general_timeout) if last_id
          "Requeue timeout"
        end
        raise "Unknown timer has been timed out" unless msg

        logger.log_info("#{msg} while processing #{job.resource_key} at id #{last_id}")
      end

      def process_job(job, start_id, labels)
        Outbox.database_switcher.use_slave do
          item_class = job.item_class
          middlewares = Middleware::Builder.new(item_process_middlewares)

          scope = item_class
            .for_processing
            .select(:id, :options)

          if item_class.has_attribute?(:bucket)
            scope = scope.where(bucket: job.buckets)
          elsif job.partition > 0
            raise "Could not filter by partition #{job.resource_key}"
          end

          scope.find_each(start: start_id, batch_size: batch_size) do |item|
            touch_thread_worker!
            item_execution_runtime.measure(labels) do
              Outbox.database_switcher.use_master do
                middleware_options = {
                  item_class: item_class,
                  # because of custom options getter which merges options value with item's default_options
                  # there may be some other fields which we haven't selected in our scope (like uuid)
                  # and we'll get ActiveModel validation error like "error: missing attribute: uuid"
                  # so just get raw attribute value here
                  options: item.attributes["options"]
                }
                middlewares.call(job, item.id, middleware_options) do
                  ProcessItem.call(job.item_class, item.id)
                end
              end
              yield item
            end
          end
        end
      end

      def log_fatal(e, job, worker_number)
        backtrace = e.backtrace.join("\n") if e.respond_to?(:backtrace)

        logger.log_error(
          "Failed processing #{job.resource_key} with error: #{e.class} #{e.message}",
          backtrace: backtrace
        )
      end

      def track_fatal(e, job, worker_number)
        job_counter
          .increment(
            job.yabeda_labels.merge(worker_number: worker_number, state: "failed"),
            by: 1
          )

        Outbox.error_tracker.error(e, **job.log_tags)
      end
    end
  end
end
