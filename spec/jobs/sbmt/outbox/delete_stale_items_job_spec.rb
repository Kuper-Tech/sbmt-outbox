# frozen_string_literal: true

describe Sbmt::Outbox::DeleteStaleItemsJob do
  let!(:item) { Fabricate(:outbox_item, created_at: created_at) }
  let(:created_at) { 1.month.ago }

  describe ".enqueue" do
    it "enqueue all item classes" do
      expect { described_class.enqueue }.to change { described_class.jobs.size }.by(1)
      expect(described_class.jobs.last["args"]).to match_array(["OutboxItem"])
    end
  end

  it "works" do
    described_class.perform_async("OutboxItem")

    expect { described_class.drain }.to change(OutboxItem, :count).by(-1)
  end

  context "when item is too yang" do
    let(:created_at) { 1.hour.ago }

    it "doesn't delete item" do
      described_class.perform_async("OutboxItem")

      expect { described_class.drain }.not_to change(OutboxItem, :count)
    end
  end
end
