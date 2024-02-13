# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool_throttler"

module Sbmt
  module Outbox
    module V2
      class ThreadPool
        delegate :logger, to: "Sbmt::Outbox"

        BREAK = Object.new.freeze
        SKIPPED = Object.new.freeze
        PROCESSED = Object.new.freeze

        def initialize(concurrency:, name: "thread_pool", throttler: nil, random_startup_delay: true, &block)
          self.concurrency = concurrency
          self.name = name
          self.throttler = throttler || ThreadPoolThrottler::Noop.new
          self.random_startup_delay = random_startup_delay
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

          result = run_threads do |task|
            logger.with_tags(worker: worker_number) do
              yield worker_number, task
            end
          end

          raise result if result.is_a?(Exception)

          nil
        ensure
          stop
        end

        def stop
          self.stopped = true
        end

        def alive?(timeout)
          return false if stopped

          deadline = Time.current - timeout
          threads.all? do |thread|
            deadline < thread.last_active_at
          end
        end

        private

        attr_accessor :concurrency, :name, :throttler, :random_startup_delay, :task_source, :task_mutex, :stopped, :threads

        def touch_worker!
          self.last_active_at = Time.current
        end

        def worker_number
          Thread.current["#{name}_worker_number:#{object_id}"]
        end

        def last_active_at
          Thread.current["#{name}_last_active_at:#{object_id}"]
        end

        def run_threads
          exception = nil

          in_threads do |worker_num|
            self.worker_number = worker_num
            touch_worker!
            # We don't want to start all threads at the same time
            sleep(rand * (worker_num + 1)) if random_startup_delay

            last_result = nil
            until exception
              throttler.wait(worker_num, last_result)

              task = next_task
              break unless task

              begin
                last_result = yield task
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
              threads.map(&:value)
            end
          ensure
            threads.each(&:kill)
            threads.clear
          end
        end

        def worker_number=(num)
          Thread.current["#{name}_worker_number:#{object_id}"] = num
        end

        def last_active_at=(at)
          Thread.current["#{name}_last_active_at:#{object_id}"] = at
        end
      end
    end
  end
end
