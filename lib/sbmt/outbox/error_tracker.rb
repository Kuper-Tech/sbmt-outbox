# frozen_string_literal: true

module Sbmt
  module Outbox
    class ErrorTracker
      class << self
        def error(message, params = {})
          Outbox.logger.log_error(message, **params)
          return unless defined?(Sentry)

          Sentry.with_scope do |scope|
            scope.set_contexts(contexts: params)

            if message.is_a?(Exception)
              Sentry.capture_exception(message, level: :error)
            else
              Sentry.capture_message(message, level: :error)
            end
          end
        end
      end
    end
  end
end
