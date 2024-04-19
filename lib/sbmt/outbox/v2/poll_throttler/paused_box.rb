# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "sbmt/outbox/v2/thread_pool"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class PausedBox < Base
          def wait(worker_num, poll_task, task_result)
            return Success(Sbmt::Outbox::V2::Throttler::NOOP_STATUS) if poll_task.item_class.config.polling_enabled?

            Success(Sbmt::Outbox::V2::Throttler::SKIP_STATUS)
          end
        end
      end
    end
  end
end
