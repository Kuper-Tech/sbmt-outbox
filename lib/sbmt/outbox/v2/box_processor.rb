# frozen_string_literal: true

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
            queue.pop
          end

          @started = false

          init_redis(redis)
        end

        def start
          raise "#{worker_name} is already started" if started
          @started = true

          thread_pool.start do |worker_number, scheduled_task|
            result = ThreadPool::PROCESSED
            last_result = Thread.current[:last_polling_result]

            next ThreadPool::SKIPPED if throttle(worker_number, scheduled_task, last_result) == PollThrottler::Base::SKIP_STATUS

            lock_task(scheduled_task) do |locked_task|
              base_labels = scheduled_task.yabeda_labels.merge(worker_name: worker_name)
              if locked_task
                labels = base_labels.merge(locked_task.yabeda_labels)
                box_worker.job_execution_runtime.measure(labels) do
                  ::Rails.application.executor.wrap do
                    logger.with_tags(**locked_task.log_tags) do
                      result = safe_process_task(worker_number, locked_task)
                    end
                  end
                end
              else
                result = ThreadPool::SKIPPED
              end

              box_worker.job_counter.increment(base_labels.merge(state: locked_task ? "processed" : "skipped"), by: 1)
            end

            Thread.current[:last_polling_result] = result || ThreadPool::PROCESSED
          ensure
            queue << scheduled_task
          end
        rescue => e
          Outbox.error_tracker.error(e)
          raise
        end

        def stop
          @started = false
          @thread_pool.stop
        end

        def ready?
          started && @thread_pool.running?
        end

        def alive?(timeout)
          return false unless ready?

          @thread_pool.alive?(timeout)
        end

        def safe_process_task(worker_number, task)
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
          self.redis = redis || ConnectionPool::Wrapper.new(size: threads_count) { RedisClientFactory.build(config.redis) }

          client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
            self.redis
          else
            ConnectionPool::Wrapper.new(size: threads_count) { Redis.new(config.redis) }
          end

          self.lock_manager = Redlock::Client.new([client], retry_count: 0)
        end

        def lock_task(scheduled_task)
          # by default there's no locking
          yield scheduled_task
        end

        def build_task_queue(boxes)
          scheduled_tasks = boxes.map do |item_class|
            Tasks::Default.new(item_class: item_class, worker_name: worker_name)
          end

          scheduled_tasks.shuffle!

          Queue.new.tap { |queue| scheduled_tasks.each { |task| queue << task } }
        end

        def log_fatal(e, task)
          backtrace = e.backtrace.join("\n") if e.respond_to?(:backtrace)

          logger.log_error(
            "Failed processing #{task} with error: #{e.class} #{e.message}",
            backtrace: backtrace
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
