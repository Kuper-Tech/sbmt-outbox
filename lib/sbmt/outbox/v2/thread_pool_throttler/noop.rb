# frozen_string_literal: true

require "sbmt/outbox/v2/thread_pool_throttler/base"

module Sbmt
  module Outbox
    module ThreadPoolThrottler
      class Noop < Base
        def wait(_worker_num, _task_result)
          # noop
        end
      end
    end
  end
end
