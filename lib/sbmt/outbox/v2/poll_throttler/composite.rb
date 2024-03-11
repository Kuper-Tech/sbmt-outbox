# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class Composite < Base
          attr_reader :throttlers

          def initialize(throttlers:)
            super()

            @throttlers = throttlers
          end

          def call(worker_num, poll_task, task_result)
            # each throttler delays polling thread by it's own rules
            # i.e. resulting delay is a sum of each throttler's ones
            results = @throttlers.map do |t|
              res = t.call(worker_num, poll_task, task_result)
              return res if res.success? && res.value! == SKIP_STATUS

              res
            end

            failure(results) || throttled(results) || Success(NOOP_STATUS)
          end

          private

          def failure(results)
            results.find { |res| res.failure? }
          end

          def throttled(results)
            results.find { |res| res.success? && res.value! == THROTTLE_STATUS }
          end
        end
      end
    end
  end
end
