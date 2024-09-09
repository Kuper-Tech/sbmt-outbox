# frozen_string_literal: true

require "sbmt/outbox/middleware/execution_context/context_item_process_middleware"

module Sbmt
  module Outbox
    module Middleware
      module ExecutionContext
        class ContextItemProcessMiddleware
          def call(item)
            ActiveSupport::ExecutionContext[:box_item] = item

            yield
          end
        end
      end
    end
  end
end
