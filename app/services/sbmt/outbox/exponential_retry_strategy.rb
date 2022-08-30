# frozen_string_literal: true

module Sbmt
  module Outbox
    class ExponentialRetryStrategy
      attr_reader :minimal_interval, :maximal_elapsed_time, :multiplier

      def initialize(minimal_interval:, maximal_elapsed_time:, multiplier:)
        @minimal_interval = minimal_interval
        @maximal_elapsed_time = maximal_elapsed_time
        @multiplier = multiplier
      end

      def call(errors_count, last_processed_at)
        backoff = ExponentialBackoff.new([minimal_interval, maximal_elapsed_time])
        backoff.multiplier = multiplier

        delay = backoff.interval_at(errors_count - 1)

        last_processed_at + delay.seconds < Time.zone.now
      end
    end
  end
end
