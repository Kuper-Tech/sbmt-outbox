# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::OpenTelemetry::TracingCreateBatchMiddleware do
  let(:tracer) { double("tracer") } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrumentation_instance) { double("instrumentation instance") } # rubocop:disable RSpec/VerifiedDoubles
  let(:item_class) { OutboxItem }
  let(:headers_first) { {header: 1} }
  let(:headers_second) { {header: 2} }
  let(:batch_attributes) do
    [
      {options: {headers: headers_first}},
      {options: {headers: headers_second}}
    ]
  end

  before do
    allow(::Sbmt::Outbox::Instrumentation::OpenTelemetryLoader).to receive(:instance).and_return(instrumentation_instance)
    allow(instrumentation_instance).to receive(:tracer).and_return(tracer)
  end

  describe ".call" do
    it "injects context into options/headers" do
      expect(tracer).to receive(:in_span).with("outbox/outbox_item create batch", kind: :producer, attributes: {
        "messaging.destination" => "OutboxItem",
        "messaging.destination_kind" => "database",
        "messaging.outbox.box_name" => "outbox_item",
        "messaging.outbox.box_type" => "outbox",
        "messaging.system" => "outbox"
      }).and_yield
      expect(::OpenTelemetry.propagation).to receive(:inject).with(headers_first)
      expect(::OpenTelemetry.propagation).to receive(:inject).with(headers_second)
      described_class.new.call(item_class, batch_attributes) {}
    end
  end
end
