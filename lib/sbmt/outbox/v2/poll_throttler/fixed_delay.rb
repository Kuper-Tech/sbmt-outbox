# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "sbmt/outbox/v2/thread_pool"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class FixedDelay < Base
          def initialize(delay:)
            super()

            @delay = delay
          end

          def wait(worker_num, poll_task, task_result)
            return Success(NOOP_STATUS) unless task_result == Sbmt::Outbox::V2::ThreadPool::PROCESSED

            sleep(@delay)

            Success(THROTTLE_STATUS)
          end
        end
      end
    end
  end
end
