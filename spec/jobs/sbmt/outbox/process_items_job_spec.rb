# frozen_string_literal: true

describe Sbmt::Outbox::ProcessItemsJob do
  subject(:perform) { items_job.perform }

  let(:items_job) { described_class.new }
  let!(:item) { Fabricate(:outbox_item, event_name: "created_order") }

  it "works" do
    expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id, timeout: 5)

    expect { perform }.to change { described_class.jobs.size }.by(1)
    expect(described_class.jobs.last["args"]).to match_array(["OutboxItem", 0])
    described_class.drain
  end

  it "skips failed items" do
    item.update!(status: OutboxItem.statuses[:failed])
    expect(Sbmt::Outbox::ProcessItem).not_to receive(:call)

    perform
    described_class.drain
  end

  context "when processing many items" do
    subject(:perform) { items_job.perform("OutboxItem") }

    let!(:item_2) { Fabricate(:outbox_item, event_name: "created_order") }
    let(:batch_size) { 1 }

    before do
      stub_const("#{described_class}::BATCH_SIZE", batch_size)
    end

    it "processes only one item" do
      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id, timeout: 5)
      expect(Sbmt::Outbox::ProcessItem).not_to receive(:call).with(OutboxItem, item_2.id, timeout: 5)
      perform
      expect(items_job).to be_requeue
    end

    context "when batch is not full" do
      let(:batch_size) { 2 }

      it "processes two items" do
        expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id, timeout: 5)
        expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item_2.id, timeout: 5)
        perform
        expect(items_job).not_to be_requeue
      end
    end
  end
end
