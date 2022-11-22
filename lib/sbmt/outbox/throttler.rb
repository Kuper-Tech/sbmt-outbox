# frozen_string_literal: true

module Sbmt
  module Outbox
    # Based on https://github.com/Shopify/limiter/blob/master/lib/limiter/rate_queue.rb
    # We cannot use that gem because we have to support Ruby 2.5,
    # but Shopify's limiter requires minimum Ruby 2.6
    class Throttler
      def initialize(limit: nil, interval: nil)
        @limit = limit
        @interval = limit
        @map = (0...@limit).map { |i| base_time + (gap * i) }
        @index = 0
        @mutex = Mutex.new
      end

      def wait
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
