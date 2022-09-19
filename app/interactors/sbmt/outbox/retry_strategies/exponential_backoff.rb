# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class ExponentialBackoff < Outbox::DryInteractor
        param :outbox_item

        def call
          delay = backoff(outbox_item.config).interval_at(outbox_item.errors_count - 1)

          still_early = outbox_item.processed_at + delay.seconds > Time.current

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
