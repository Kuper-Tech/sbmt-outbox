# frozen_string_literal: true

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

          def wait(worker_num, poll_task, task_result)
            # each throttler delays polling thread by it's own rules
            # i.e. resulting delay is a sum of each throttler's ones
            results = @throttlers.map { |t| t.wait(worker_num, poll_task, task_result) }
            results.find { |r| r.success? } || Failure(SKIP_STATUS)
          end
        end
      end
    end
  end
end
