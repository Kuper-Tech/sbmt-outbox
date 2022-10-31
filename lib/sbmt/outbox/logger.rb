# frozen_string_literal: true

module Sbmt
  module Outbox
    class Logger
      delegate :logger, to: :Rails

      def log_info(message, **params)
        with_tags(**params) do
          logger.info(message)
        end
      end

      def log_error(message, **params)
        with_tags(**params) do
          logger.error(message)
        end
      end

      def log_success(message, **params)
        log_info(message, status: "success", **params)
      end

      def log_failure(message, **params)
        log_error(message, status: "failure", **params)
      end

      def with_tags(**params)
        logger.tagged(**params) do
          yield
        end
      end
    end
  end
end
