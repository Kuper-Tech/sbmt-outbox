# frozen_string_literal: true

module Sbmt
  module Outbox
    module Middleware
      module OpenTelemetry
        class TracingItemProcessMiddleware
          def call(item)
            return yield unless defined?(::OpenTelemetry)

            item_class = item.class
            item_options = item.options || {}
            item_options_headers = item_options[:headers] || item_options["headers"]

            return yield unless item_class && item_options_headers

            span_attributes = {
              "messaging.system" => "outbox",
              "messaging.outbox.item_id" => item.id.to_s,
              "messaging.outbox.box_type" => item_class.box_type.to_s,
              "messaging.outbox.box_name" => item_class.box_name,
              "messaging.outbox.owner" => item_class.owner,
              "messaging.destination" => item_class.name,
              "messaging.destination_kind" => "database",
              "messaging.operation" => "process"
            }

            extracted_context = ::OpenTelemetry.propagation.extract(item_options_headers)
            ::OpenTelemetry::Context.with_current(extracted_context) do
              tracer.in_span(span_name(item_class), attributes: span_attributes.compact, kind: :consumer) do
                yield
              end
            end
          end

          private

          def tracer
            ::Sbmt::Outbox::Instrumentation::OpenTelemetryLoader.instance.tracer
          end

          def span_name(item_class)
            "#{item_class.box_type}/#{item_class.box_name} process item"
          end
        end
      end
    end
  end
end
