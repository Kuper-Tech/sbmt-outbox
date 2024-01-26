# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::OpenTelemetry::TracingItemProcessMiddleware do
  let(:tracer) { double("tracer") } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrumentation_instance) { double("instrumentation instance") } # rubocop:disable RSpec/VerifiedDoubles
  let(:headers) { {"SOME_TELEMETRY_HEADER" => "telemetry_value"} }
  let(:inbox_item) { create(:inbox_item, options: {headers: headers}) }

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
        "messaging.outbox.item_id" => inbox_item.id.to_s,
        "messaging.system" => "outbox"
      }).and_yield
      expect(::OpenTelemetry.propagation).to receive(:extract).with(a_hash_including(headers))
      described_class.new.call(inbox_item) {}
    end
  end
end
