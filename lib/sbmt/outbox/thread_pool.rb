# frozen_string_literal: true

require "sbmt/outbox/throttler"

module Sbmt
  module Outbox
    class ThreadPool
      BREAK = Object.new.freeze

      def initialize(&block)
        self.task_source = block
        self.task_mutex = Mutex.new
        self.stopped = true
      end

      def next_task
        task_mutex.synchronize do
          return if stopped
          item = task_source.call

          if item == BREAK
            self.stopped = true
            return
          end

          item
        end
      end

      def start(concurrency:)
        self.stopped = false
        result = run_threads(count: concurrency) do |item|
          yield worker_number, item
        end

        raise result if result.is_a?(Exception)
        nil
      ensure
        self.stopped = true
      end

      def stop
        self.stopped = true
      end

      def worker_number
        Thread.current["thread_pool_worker_number:#{object_id}"]
      end

      private

      attr_accessor :task_source, :task_mutex, :stopped

      def run_threads(count:)
        exception = nil

        in_threads(count: count) do |worker_num|
          self.worker_number = worker_num
          # We don't want to start all threads at the same time
          random_sleep = rand * (worker_num + 1)

          throttler = Throttler.new(
            limit: Outbox.config.worker.rate_limit,
            interval: Outbox.config.worker.rate_interval + random_sleep
          )

          sleep(random_sleep)

          while !exception && throttler.wait && (item = next_task)
            begin
              yield item
            rescue Exception => e # rubocop:disable Lint/RescueException
              exception = e
            end
          end
        end

        exception
      end

      def in_threads(count:)
        threads = []

        Thread.handle_interrupt(Exception => :never) do
          Thread.handle_interrupt(Exception => :immediate) do
            count.times do |i|
              threads << Thread.new { yield(i) }
            end
            threads.map(&:value)
          end
        ensure
          threads.each(&:kill)
        end
      end

      def worker_number=(num)
        Thread.current["thread_pool_worker_number:#{object_id}"] = num
      end
    end
  end
end
