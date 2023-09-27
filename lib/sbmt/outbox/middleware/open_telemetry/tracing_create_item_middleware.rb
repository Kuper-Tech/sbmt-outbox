# frozen_string_literal: true

module Sbmt
  module Outbox
    module Middleware
      module OpenTelemetry
        class TracingCreateItemMiddleware
          def call(item_class, item_attributes)
            return yield unless defined?(::OpenTelemetry)

            span_attributes = {
              "messaging.system" => "outbox",
              "messaging.outbox.box_type" => item_class.box_type.to_s,
              "messaging.outbox.box_name" => item_class.box_name,
              "messaging.outbox.owner" => item_class.owner,
              "messaging.destination" => item_class.name,
              "messaging.destination_kind" => "database"
            }

            options = item_attributes[:options] ||= {}
            headers = options[:headers] || options["headers"]
            headers ||= options[:headers] ||= {}
            tracer.in_span(span_name(item_class), attributes: span_attributes.compact, kind: :producer) do
              ::OpenTelemetry.propagation.inject(headers)
              yield
            end
          end

          private

          def tracer
            ::Sbmt::Outbox::Instrumentation::OpenTelemetryLoader.instance.tracer
          end

          def span_name(item_class)
            "#{item_class.box_type}/#{item_class.box_name} create item"
          end
        end
      end
    end
  end
end
