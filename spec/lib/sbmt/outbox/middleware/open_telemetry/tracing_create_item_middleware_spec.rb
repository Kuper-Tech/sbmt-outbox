# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::OpenTelemetry::TracingCreateItemMiddleware do
  let(:tracer) { double("tracer") } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrumentation_instance) { double("instrumentation instance") } # rubocop:disable RSpec/VerifiedDoubles
  let(:item_class) { OutboxItem }
  let(:headers) { {} }
  let(:item_attrs) { {options: {headers: headers}} }

  before do
    allow(::Sbmt::Outbox::Instrumentation::OpenTelemetryLoader).to receive(:instance).and_return(instrumentation_instance)
    allow(instrumentation_instance).to receive(:tracer).and_return(tracer)
  end

  describe ".call" do
    it "injects context into options/headers" do
      expect(tracer).to receive(:in_span).with("outbox/outbox_item create item", kind: :producer, attributes: {
        "messaging.destination" => "OutboxItem",
        "messaging.destination_kind" => "database",
        "messaging.outbox.box_name" => "outbox_item",
        "messaging.outbox.box_type" => "outbox",
        "messaging.system" => "outbox"
      }).and_yield
      expect(::OpenTelemetry.propagation).to receive(:inject).with(headers)
      described_class.new.call(item_class, item_attrs) {}
    end
  end
end
