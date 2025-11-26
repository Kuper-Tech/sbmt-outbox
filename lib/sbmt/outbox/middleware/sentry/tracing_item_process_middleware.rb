# frozen_string_literal: true

require "sbmt/outbox/middleware/sentry/transaction"

module Sbmt
  module Outbox
    module Middleware
      module Sentry
        class TracingItemProcessMiddleware
          include Transaction

          attr_reader :new_transaction

          def call(item)
            return yield unless ::Sentry.initialized?

            scope = ::Sentry.get_current_scope

            # transaction will be nil if sentry tracing is not enabled
            transaction = scope&.get_transaction || start_transaction(scope, item.class)
            span = transaction&.start_child(op: op(item.class), description: "Starting item processing")
            span&.set_data(:item_id, item.id)

            begin
              result = yield
            rescue
              finish_span(span, 500)
              finish_sentry_transaction(scope, transaction, 500) if new_transaction
              raise
            end

            finish_span(span, 200)
            finish_sentry_transaction(scope, transaction, 200) if new_transaction

            result
          end

          private

          def finish_span(span, status)
            return unless span

            span.set_data(:status, status)
            span.finish
          end

          def start_transaction(scope, item_class)
            @new_transaction = true
            start_sentry_transaction(scope, op(item_class), transaction_name(item_class), tags(item_class))
          end

          def transaction_name(item_class)
            "Sbmt.#{item_class.box_type.capitalize}.#{item_class.box_name.capitalize}"
          end

          def tags(item_class)
            {box_type: item_class.box_type, box_name: item_class.box_name}
          end

          def op(item_class)
            "sbmt.#{item_class.box_type.downcase}.item_process"
          end
        end
      end
    end
  end
end
