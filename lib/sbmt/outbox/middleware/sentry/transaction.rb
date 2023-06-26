# frozen_string_literal: true

module Sbmt::Outbox::Middleware
  module Sentry
    module Transaction
      def start_sentry_transaction(scope, op, name, tags = {})
        trace_id = SecureRandom.base58
        scope&.set_tags(tags.merge(trace_id: trace_id))
        transaction = ::Sentry.start_transaction(op: op, name: name)
        scope&.set_span(transaction) if transaction

        transaction
      end

      def finish_sentry_transaction(scope, transaction, status)
        return unless transaction

        transaction.set_http_status(status)
        transaction.finish
        scope.clear
      end
    end
  end
end
