# frozen_string_literal: true

require "sbmt/outbox/v2/throttler"
require "sbmt/outbox/v2/thread_pool"
require "sbmt/outbox/v2/tasks/default"

module Sbmt
  module Outbox
    module V2
      class BoxProcessor
        delegate :config, :logger, to: "Sbmt::Outbox"
        delegate :box_worker, to: "Yabeda"
        attr_reader :started, :threads_count, :worker_name

        def initialize(boxes:, threads_count:, name: "abstract_worker", redis: nil)
          @threads_count = threads_count
          @worker_name = name

          @queue = build_task_queue(boxes)
          @thread_pool = ThreadPool.new(
            concurrency: threads_count,
            name: "#{name}_thread_pool"
          ) do
            logger.log_debug("#{name}_thread_pool: requesting next task from queue")
            task = queue.pop
            logger.log_debug("#{name}_thread_pool: received task #{task&.item_class&.box_name}")

            task
          end

          @started = false

          init_redis(redis)
        end

        def start
          logger.log_info("#{worker_name}: starting with #{@threads_count} threads")

          raise "#{worker_name} is already started" if started
          @started = true

          logger.log_info("#{worker_name}: starting thread pool")
          thread_pool.start do |worker_number, scheduled_task|
            logger.log_debug("#{worker_name}: worker #{worker_number} processing scheduled task for box #{scheduled_task&.item_class&.box_name}")

            result = ThreadPool::PROCESSED
            last_result = Thread.current[:last_polling_result]

            throttling_res = throttle(worker_number, scheduled_task, last_result)
            next ThreadPool::SKIPPED if throttling_res&.value_or(nil) == Sbmt::Outbox::V2::Throttler::SKIP_STATUS

            lock_task(scheduled_task) do |locked_task|
              base_labels = scheduled_task.yabeda_labels.merge(worker_name: worker_name)
              if locked_task
                labels = base_labels.merge(locked_task.yabeda_labels)
                box_worker.job_execution_runtime.measure(labels) do
                  ::Rails.application.executor.wrap do
                    logger.with_tags(**locked_task.log_tags) do
                      logger.log_debug("#{worker_name}: worker #{worker_number} processing locked task")
                      result = safe_process_task(worker_number, locked_task)
                      logger.log_debug("#{worker_name}: worker #{worker_number} completed locked task")
                    end
                  end
                end
              else
                result = ThreadPool::SKIPPED
              end

              box_worker.job_counter.increment(base_labels.merge(state: locked_task ? "processed" : "skipped"), by: 1)
            end

            logger.log_debug("#{worker_name}: worker #{worker_number} finished processing")
            Thread.current[:last_polling_result] = result || ThreadPool::PROCESSED
          ensure
            logger.log_debug("#{worker_name}: returning task to queue")
            queue << scheduled_task
          end
        rescue => e
          logger.log_error("#{worker_name}: thread pool encountered error during start: #{e.inspect}")
          Outbox.error_tracker.error(e)
          raise
        end

        def stop
          logger.log_info("#{worker_name}: stopping worker")
          @started = false
          @thread_pool.stop
          logger.log_info("#{worker_name}: worker stopped")
        end

        def ready?
          logger.log_debug("#{worker_name}: checking if ready")
          unless started
            logger.log_debug("#{worker_name}: checking if ready: not started")
            return false
          end

          result = @thread_pool.running?
          unless result
            logger.log_debug("#{worker_name}: checking if ready: thread_pool is not running")
            return false
          end

          logger.log_debug("#{worker_name}: ready? #{result}")
          result
        end

        def alive?(timeout)
          logger.log_debug("#{worker_name}: checking if alive with timeout #{timeout}")

          unless ready?
            logger.log_debug("#{worker_name}: checking if alive: not ready")
            return false
          end

          result = @thread_pool.alive?(timeout)
          unless result
            logger.log_info("#{worker_name}: checking if alive: thread_pool is not alive")
            return false
          end

          logger.log_debug("#{worker_name}: alive? #{result}")
          result
        end

        def safe_process_task(worker_number, task)
          logger.log_debug("#{worker_name}: safely processing task for worker #{worker_number}")
          process_task(worker_number, task)
        rescue => e
          log_fatal(e, task)
          track_fatal(e, task)
        end

        def throttle(_worker_number, _scheduled_task, _result)
          # noop by default
          # IMPORTANT: method is called from thread-pool, i.e. code must be thread-safe
        end

        def process_task(_worker_number, _task)
          raise NotImplementedError, "Implement #process_task for Sbmt::Outbox::V2::BoxProcessor"
        end

        private

        attr_accessor :queue, :thread_pool, :redis, :lock_manager

        def init_redis(redis)
          logger.log_info("#{worker_name}: initializing Redis connection")

          self.redis = redis || ConnectionPool::Wrapper.new(size: threads_count) { RedisClientFactory.build(config.redis) }

          client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
            self.redis
          else
            ConnectionPool::Wrapper.new(size: threads_count) { Redis.new(config.redis) }
          end

          self.lock_manager = Redlock::Client.new([client], retry_count: 0)
          logger.log_info("#{worker_name}: Redis initialized")
        end

        def lock_task(scheduled_task)
          # by default there's no locking
          yield scheduled_task
        end

        def build_task_queue(boxes)
          scheduled_tasks = boxes.map do |item_class|
            Tasks::Default.new(item_class: item_class, worker_name: worker_name)
          end

          logger.log_debug("#{worker_name}: building task queue with #{scheduled_tasks.length} tasks")
          scheduled_tasks.shuffle!
          Queue.new.tap { |queue| scheduled_tasks.each { |task| queue << task } }
        end

        def log_fatal(e, task)
          backtrace = e.backtrace.join("\n") if e.respond_to?(:backtrace)

          logger.log_error(
            "Failed processing #{task} with error: #{e.class} #{e.message}",
            stacktrace: backtrace
          )
        end

        def track_fatal(e, task)
          box_worker.job_counter.increment(task.yabeda_labels.merge(state: "failed"))
          Outbox.error_tracker.error(e, **task.log_tags)
        end
      end
    end
  end
end
