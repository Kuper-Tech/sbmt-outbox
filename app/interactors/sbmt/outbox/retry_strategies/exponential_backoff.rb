# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class ExponentialBackoff < Base
        def call
          delay = backoff(item.config).interval_at(item.errors_count - 1)

          still_early = item.processed_at + delay.seconds > Time.current

          if still_early
            Failure(:skip_processing)
          else
            Success()
          end
        end

        private

        def backoff(config)
          @backoff ||= ::ExponentialBackoff.new([
            config.minimal_retry_interval,
            config.maximal_retry_interval
          ]).tap do |x|
            x.multiplier = config.multiplier_retry_interval
          end
        end
      end
    end
  end
end
