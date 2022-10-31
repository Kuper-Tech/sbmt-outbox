# frozen_string_literal: true

describe Sbmt::Outbox::ProcessInboxItemsJob do
  it { expect(described_class.item_classes).to eq [InboxItem] }
end
