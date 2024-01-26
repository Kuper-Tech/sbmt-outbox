# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::Sentry::TracingItemProcessMiddleware do
  let(:outbox_item) { create(:outbox_item) }
  let(:scope) { double("scope") } # rubocop:disable RSpec/VerifiedDoubles
  let(:trace_id) { "trace-id" }

  it "skips tracing if sentry is not initialized" do
    allow(::Sentry).to receive(:initialized?).and_return(false)
    expect(::Sentry).not_to receive(:start_transaction)

    expect { described_class.new.call(outbox_item) {} }.not_to raise_error
  end

  it "sets up sentry transaction" do
    allow(::Sentry).to receive(:initialized?).and_return(true)
    expect(::Sentry).to receive(:get_current_scope).and_return(scope)
    expect(scope).to receive(:get_transaction).and_return(nil)
    expect(scope).to receive(:set_tags).with hash_including(:trace_id, box_type: :outbox, box_name: "outbox_item")
    expect(::Sentry).to receive(:start_transaction)
      .with(op: "sbmt.outbox.item_process", name: "Sbmt.Outbox.Outbox_item")
      .and_return(nil)

    expect { described_class.new.call(outbox_item) {} }.not_to raise_error
  end
end
