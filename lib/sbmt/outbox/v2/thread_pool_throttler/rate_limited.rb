# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool_throttler/base"

module Sbmt
  module Outbox
    module ThreadPoolThrottler
      class RateLimited < Base
        def initialize(limit: nil, interval: nil)
          @limit = limit
          @interval = interval
          @map = (0...@limit).map { |i| base_time + (gap * i) }
          @index = 0
          @mutex = Mutex.new
        end

        def wait(worker_num, task_result)
          time = nil

          @mutex.synchronize do
            time = @map[@index]

            sleep_until(time + @interval)

            @map[@index] = now
            @index = (@index + 1) % @limit
          end

          time
        end

        private

        def sleep_until(time)
          period = time - now
          sleep(period) if period > 0
        end

        def base_time
          now - @interval
        end

        def gap
          @interval.to_f / @limit.to_f
        end

        def now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
