# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool_throttler/base"

module Sbmt
  module Outbox
    module ThreadPoolThrottler
      class FixedDelay < Base
        def initialize(delay:)
          super
          @delay = delay
        end

        def wait(_worker_num, task_result)
          sleep(@delay) if task_result == Sbmt::Outbox::V2::ThreadPool::PROCESSED
        end
      end
    end
  end
end
