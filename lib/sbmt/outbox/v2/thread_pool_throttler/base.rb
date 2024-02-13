# frozen_string_literal: true

module Sbmt
  module Outbox
    module ThreadPoolThrottler
      class Base
        def wait(_worker_num, _task_result)
          raise NotImplementedError, "Implement #wait for Sbmt::Outbox::Throttler::Base"
        end
      end
    end
  end
end
