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
        self.lock_manager = Redlock::Client.new(config.redis_servers, retry_count: 0)
        # TODO: add connection pool? I cannot access to the `@servers` variable in RedLock
        self.redis = build_redis(config.redis_servers.first)
        self.thread_workers = {}
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
                  process_job_with_errors(job, worker_number, labels)
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

      def build_redis(server)
        case server
        when String
          Redis.new(url: server)
        when Hash
          Redis.new(**server)
        else
          server
        end
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

      def process_job_with_errors(job, worker_number, labels)
        attempt ||= 1
        start_id ||= redis.getdel("#{job.resource_path}:last_id").to_i + 1
        logger.log_info("Start processing #{job.resource_key} from id #{start_id}")
        process_job_with_timeouts(job, start_id, labels)
      rescue ActiveRecord::StatementInvalid => e
        attempt += 1
        log_fatal(e, job, worker_number)

        if attempt > 3
          track_fatal(e, job, worker_number)
          raise e # exit with error
        end

        ::ActiveRecord::Base.clear_active_connections!
        retry
      rescue => e
        log_fatal(e, job, worker_number)
        track_fatal(e, job, worker_number)
      end

      def process_job_with_timeouts(job, start_id, labels)
        count = 0
        last_id = nil
        lock_timer = Cutoff.new(general_timeout)
        requeue_timer = Cutoff.new(cutoff_timeout)
        middlewares = Middleware::Builder.new(batch_process_middlewares)

        middlewares.call(job) do
          process_job(job, start_id, labels) do |item|
            job_items_counter.increment(labels, by: 1)
            last_id = item.id
            count += 1
            lock_timer.checkpoint!
            requeue_timer.checkpoint!
          end
        end

        logger.log_info("Finish processing #{job.resource_key} at id #{last_id}")
      rescue Cutoff::CutoffExceededError
        job_timeout_counter.increment(labels, by: 1)

        msg = if lock_timer.exceeded?
          "Lock timeout"
        elsif requeue_timer.exceeded?
          redis.setex("#{job.resource_path}:last_id", general_timeout, last_id) if last_id
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
            .select(:id)

          if item_class.has_attribute?(:bucket)
            scope = scope.where(bucket: job.buckets)
          elsif job.partition > 1
            raise "Could not filter by partition #{job.resource_key}"
          end

          scope.find_each(start: start_id, batch_size: batch_size) do |item|
            touch_thread_worker!
            item_execution_runtime.measure(labels) do
              Outbox.database_switcher.use_master do
                middlewares.call(job, item.id) do
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
          "Failed processing #{job.resource_key} with error: #{e.message}",
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
