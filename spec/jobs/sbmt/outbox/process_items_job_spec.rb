# frozen_string_literal: true

describe Sbmt::Outbox::ProcessItemsJob do
  subject(:perform) { described_class.new.perform }

  let!(:item) { Fabricate(:outbox_item, event_name: "created_order") }

  it "works" do
    expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, item.id)

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
end
