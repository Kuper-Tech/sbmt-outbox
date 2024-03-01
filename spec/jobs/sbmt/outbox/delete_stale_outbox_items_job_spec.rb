# frozen_string_literal: true

describe Sbmt::Outbox::DeleteStaleOutboxItemsJob do
  it { expect(described_class.item_classes).to eq [OutboxItem, Combined::OutboxItem] }
end
