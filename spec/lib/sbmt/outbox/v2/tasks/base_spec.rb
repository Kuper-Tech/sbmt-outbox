# frozen_string_literal: true

require "sbmt/outbox/v2/tasks/base"

describe Sbmt::Outbox::V2::Tasks::Base do
  let(:worker_name) { "worker" }

  it "properly formats log tags" do
    expect(described_class.new(item_class: InboxItem, worker_name: worker_name).log_tags).to eq(box_name: "inbox_item", box_type: :inbox)
    expect(described_class.new(item_class: OutboxItem, worker_name: worker_name).log_tags).to eq(box_name: "outbox_item", box_type: :outbox)
    expect(described_class.new(item_class: Combined::OutboxItem, worker_name: worker_name).log_tags).to eq(box_name: "combined/outbox_item", box_type: :outbox)
  end

  it "properly formats yabeda labels" do
    expect(described_class.new(item_class: InboxItem, worker_name: worker_name).yabeda_labels).to eq(name: "inbox_item", type: :inbox, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: OutboxItem, worker_name: worker_name).yabeda_labels).to eq(name: "outbox_item", type: :outbox, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: Combined::OutboxItem, worker_name: worker_name).yabeda_labels).to eq(name: "combined-outbox_item", type: :outbox, worker_name: "worker", worker_version: 2)
  end
end
