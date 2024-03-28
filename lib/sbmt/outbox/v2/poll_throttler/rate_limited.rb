# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "ruby-limiter"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class RateLimited < Base
          attr_reader :queues

          def initialize(limit: nil, interval: nil, balanced: true)
            @limit = limit
            @interval = interval
            @balanced = balanced
            @queues = {}
            @mutex = Mutex.new
          end

          def wait(_worker_num, poll_task, _task_result)
            queue_for(poll_task).shift

            Success(Sbmt::Outbox::V2::Throttler::THROTTLE_STATUS)
          end

          private

          def queue_for(task)
            key = task.item_class.box_name
            return @queues[key] if @queues.key?(key)

            @mutex.synchronize do
              return @queues[key] if @queues.key?(key)

              @queues[key] = Limiter::RateQueue.new(
                @limit, interval: @interval, balanced: @balanced
              )
            end
          end
        end
      end
    end
  end
end
