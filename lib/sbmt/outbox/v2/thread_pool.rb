# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      class ThreadPool
        delegate :logger, to: "Sbmt::Outbox"

        BREAK = Object.new.freeze
        SKIPPED = Object.new.freeze
        PROCESSED = Object.new.freeze

        def initialize(concurrency:, name: "thread_pool", random_startup_delay: true, start_async: true, &block)
          self.concurrency = concurrency
          self.name = name
          self.random_startup_delay = random_startup_delay
          self.start_async = start_async
          self.task_source = block
          self.task_mutex = Mutex.new
          self.stopped = true
          self.threads = Concurrent::Array.new
        end

        def next_task
          task_mutex.synchronize do
            return if stopped
            task = task_source.call

            if task == BREAK
              self.stopped = true
              return
            end

            task
          end
        end

        def start
          self.stopped = false

          mode = start_async ? "async" : "sync"
          logger.log_info("#{name}: starting #{concurrency} threads in #{mode} mode")

          result = run_threads do |task|
            logger.with_tags(worker: worker_number) do
              yield worker_number, task
            end
          end

          logger.log_info("#{name}: threads started")

          raise result if result.is_a?(Exception)
        end

        def stop
          self.stopped = true

          threads.map(&:join) if start_async
        ensure
          stop_threads
        end

        def running?
          return false if stopped

          true
        end

        def alive?(timeout)
          return false if stopped

          deadline = Time.current - timeout
          threads.all? do |thread|
            last_active_at = last_active_at(thread)
            return false unless last_active_at

            deadline < last_active_at
          end
        end

        private

        attr_accessor :concurrency, :name, :random_startup_delay, :task_source, :task_mutex, :stopped, :start_async, :threads

        def touch_worker!
          self.last_active_at = Time.current
        end

        def worker_number(thread = Thread.current)
          thread.thread_variable_get("#{name}_worker_number:#{object_id}")
        end

        def last_active_at(thread = Thread.current)
          thread.thread_variable_get("#{name}_last_active_at:#{object_id}")
        end

        def run_threads
          exception = nil

          in_threads do |worker_num|
            self.worker_number = worker_num
            # We don't want to start all threads at the same time
            sleep(rand * (worker_num + 1)) if random_startup_delay

            touch_worker!

            until exception
              task = next_task
              break unless task

              touch_worker!

              begin
                yield task
              rescue Exception => e # rubocop:disable Lint/RescueException
                exception = e
              end
            end
          end

          exception
        end

        def in_threads
          Thread.handle_interrupt(Exception => :never) do
            Thread.handle_interrupt(Exception => :immediate) do
              concurrency.times do |i|
                threads << Thread.new { yield(i) }
              end
              threads.map(&:value) unless start_async
            end
          ensure
            stop_threads unless start_async
          end
        end

        def stop_threads
          threads.each(&:kill)
          threads.clear
        end

        def worker_number=(num)
          Thread.current.thread_variable_set("#{name}_worker_number:#{object_id}", num)
        end

        def last_active_at=(at)
          Thread.current.thread_variable_set("#{name}_last_active_at:#{object_id}", at)
        end
      end
    end
  end
end
