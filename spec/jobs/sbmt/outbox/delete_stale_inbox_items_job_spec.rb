# frozen_string_literal: true

describe Sbmt::Outbox::DeleteStaleInboxItemsJob do
  it { expect(described_class.item_classes).to eq [InboxItem] }
end
