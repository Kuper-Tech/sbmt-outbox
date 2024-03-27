# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "ruby-limiter"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class RateLimited < Base
          def initialize(limit: nil, interval: nil, balanced: true)
            @queue = Limiter::RateQueue.new(limit, interval: interval, balanced: balanced)
          end

          def wait(_worker_num, _poll_task, _task_result)
            @queue.shift

            Success(Sbmt::Outbox::V2::Throttler::THROTTLE_STATUS)
          end
        end
      end
    end
  end
end
