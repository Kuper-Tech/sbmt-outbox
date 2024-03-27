# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class Noop < Base
          def wait(worker_num, poll_task, _task_result)
            Success(Sbmt::Outbox::V2::Throttler::NOOP_STATUS)
          end
        end
      end
    end
  end
end
