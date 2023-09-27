# frozen_string_literal: true

describe Sbmt::Outbox::Middleware::Sentry::TracingItemProcessMiddleware do
  let(:item_id) { 1 }
  let(:job) { OpenStruct.new(log_tags: {}) }
  let(:scope) { double("scope") } # rubocop:disable RSpec/VerifiedDoubles
  let(:trace_id) { "trace-id" }

  it "skips tracing if sentry is not initialized" do
    expect(::Sentry).to receive(:initialized?).and_return(false)
    expect(::Sentry).not_to receive(:start_transaction)

    expect { described_class.new.call(job, item_id, {}) {} }.not_to raise_error
  end

  it "sets up sentry transaction" do
    expect(::Sentry).to receive(:initialized?).and_return(true)
    expect(::Sentry).to receive(:get_current_scope).and_return(scope)
    expect(scope).to receive(:get_transaction).and_return(nil)
    expect(scope).to receive(:set_tags).with hash_including(:trace_id)
    expect(::Sentry).to receive(:start_transaction).and_return(nil)

    expect { described_class.new.call(job, item_id, {}) {} }.not_to raise_error
  end
end
