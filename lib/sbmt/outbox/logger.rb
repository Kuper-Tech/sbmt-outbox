# frozen_string_literal: true

module Sbmt
  module Outbox
    class Logger
      delegate :logger, to: :Rails

      def log_success(message, outbox_name:, **params)
        log_with_tags(outbox_name: outbox_name, status: "success", **params) do
          logger.info(message)
        end
      end

      def log_failure(message, outbox_name:, **params)
        log_with_tags(outbox_name: outbox_name, status: "failure", **params) do
          logger.error(message)
        end
      end

      def log_with_tags(outbox_name:, **params)
        logger.tagged(outbox_name: outbox_name, **params) do
          yield
        end
      end
    end
  end
end
