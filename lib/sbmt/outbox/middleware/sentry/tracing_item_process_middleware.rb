# frozen_string_literal: true

require "sbmt/outbox/middleware/sentry/transaction"

module Sbmt::Outbox::Middleware
  module Sentry
    class TracingItemProcessMiddleware
      include Transaction

      attr_reader :new_transaction

      def call(job, item_id)
        return yield unless ::Sentry.initialized?

        scope = ::Sentry.get_current_scope

        # transaction will be nil if sentry tracing is not enabled
        transaction = scope&.get_transaction || start_transaction(scope, job)
        span = transaction&.start_child(op: op(job), description: "Starting item processing")
        span&.set_data(:item_id, item_id)

        begin
          yield
        rescue
          finish_span(span, 500)
          finish_sentry_transaction(scope, transaction, 500) if new_transaction
          raise
        end

        finish_span(span, 200)
        finish_sentry_transaction(scope, transaction, 200) if new_transaction
      end

      private

      def finish_span(span, status)
        return unless span

        span.set_data(:status, status)
        span.finish
      end

      def start_transaction(scope, job)
        @new_transaction = true
        start_sentry_transaction(scope, op(job), transaction_name(job), job.log_tags)
      end

      def transaction_name(job)
        "Sbmt.#{job.log_tags[:box_type]&.capitalize}.#{job.log_tags[:box_name]&.capitalize}"
      end

      def op(job)
        "sbmt.#{job.log_tags[:box_type]&.downcase}.item_process"
      end
    end
  end
end
