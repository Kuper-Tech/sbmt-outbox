# frozen_string_literal: true

require "opentelemetry"
require "opentelemetry-common"
require "opentelemetry-instrumentation-base"

require_relative "../middleware/open_telemetry/tracing_create_item_middleware"
require_relative "../middleware/open_telemetry/tracing_create_batch_middleware"
require_relative "../middleware/open_telemetry/tracing_item_process_middleware"

module Sbmt
  module Outbox
    module Instrumentation
      class OpenTelemetryLoader < ::OpenTelemetry::Instrumentation::Base
        install do |_config|
          require_dependencies

          ::Sbmt::Outbox.config.create_item_middlewares.push("Sbmt::Outbox::Middleware::OpenTelemetry::TracingCreateItemMiddleware")
          ::Sbmt::Outbox.config.create_batch_middlewares.push("Sbmt::Outbox::Middleware::OpenTelemetry::TracingCreateBatchMiddleware")
          ::Sbmt::Outbox.config.item_process_middlewares.push("Sbmt::Outbox::Middleware::OpenTelemetry::TracingItemProcessMiddleware")
        end

        present do
          true
        end

        private

        def require_dependencies
          require_relative "../middleware/open_telemetry/tracing_create_item_middleware"
          require_relative "../middleware/open_telemetry/tracing_create_batch_middleware"
          require_relative "../middleware/open_telemetry/tracing_item_process_middleware"
        end
      end
    end
  end
end
