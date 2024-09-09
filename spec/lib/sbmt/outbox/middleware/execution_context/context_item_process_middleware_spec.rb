# frozen_string_literal: true

require "sbmt/outbox/middleware/execution_context/context_item_process_middleware"

describe Sbmt::Outbox::Middleware::ExecutionContext::ContextItemProcessMiddleware do
  let(:outbox_item) { create(:outbox_item) }

  before do
    skip("not supported in the current Rails version") unless defined?(ActiveSupport::ExecutionContext)
  end

  it "sets execution context" do
    described_class.new.call(outbox_item) {}
    expect(ActiveSupport::ExecutionContext.to_h[:box_item]).to eq outbox_item
  end
end
