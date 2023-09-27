# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::OpenTelemetry::TracingItemProcessMiddleware do
  let(:tracer) { double("tracer") } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrumentation_instance) { double("instrumentation instance") } # rubocop:disable RSpec/VerifiedDoubles
  let(:headers) { {} }
  let(:options) do
    {
      item_class: InboxItem,
      options: {headers: headers}
    }
  end

  before do
    allow(::Sbmt::Outbox::Instrumentation::OpenTelemetryLoader).to receive(:instance).and_return(instrumentation_instance)
    allow(instrumentation_instance).to receive(:tracer).and_return(tracer)
  end

  describe ".call" do
    it "injects context into message headers" do
      expect(tracer).to receive(:in_span).with("inbox/inbox_item process item", kind: :consumer, attributes: {
        "messaging.destination" => "InboxItem",
        "messaging.destination_kind" => "database",
        "messaging.operation" => "process",
        "messaging.outbox.box_name" => "inbox_item",
        "messaging.outbox.box_type" => "inbox",
        "messaging.outbox.item_id" => "1",
        "messaging.system" => "outbox"
      }).and_yield
      expect(::OpenTelemetry.propagation).to receive(:extract).with(headers)
      described_class.new.call("job", 1, options) {}
    end
  end
end
