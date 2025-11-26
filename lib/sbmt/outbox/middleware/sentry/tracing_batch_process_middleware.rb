# frozen_string_literal: true

require "sbmt/outbox/middleware/sentry/transaction"

module Sbmt
  module Outbox
    module Middleware
      module Sentry
        class TracingBatchProcessMiddleware
          include Transaction

          def call(job)
            return yield unless ::Sentry.initialized?

            scope = ::Sentry.get_current_scope

            # transaction will be nil if sentry tracing is not enabled
            transaction = start_transaction(scope, job)

            begin
              result = yield
            rescue
              finish_sentry_transaction(scope, transaction, 500)
              raise
            end

            finish_sentry_transaction(scope, transaction, 200)

            result
          end

          private

          def start_transaction(scope, job)
            start_sentry_transaction(scope, op(job), transaction_name(job), job.log_tags)
          end

          def op(job)
            "sbmt.#{job.log_tags[:box_type]&.downcase}.batch_process"
          end

          def transaction_name(job)
            "Sbmt.#{job.log_tags[:box_type]&.capitalize}.#{job.log_tags[:box_name]&.capitalize}"
          end
        end
      end
    end
  end
end
