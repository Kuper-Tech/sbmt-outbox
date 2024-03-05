# frozen_string_literal: true

require "sbmt/outbox/v2/tasks/process"

describe Sbmt::Outbox::V2::Tasks::Process do
  let(:worker_name) { "worker" }
  let(:bucket) { 0 }
  let(:ids) { [0, 1] }

  it "properly formats log tags" do
    expect(described_class.new(item_class: InboxItem, worker_name: worker_name, bucket: bucket, ids: ids).log_tags).to eq(box_name: "inbox_item", box_type: :inbox, bucket: 0, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: OutboxItem, worker_name: worker_name, bucket: bucket, ids: ids).log_tags).to eq(box_name: "outbox_item", box_type: :outbox, bucket: 0, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: Combined::OutboxItem, worker_name: worker_name, bucket: bucket, ids: ids).log_tags).to eq(box_name: "combined/outbox_item", box_type: :outbox, bucket: 0, worker_name: "worker", worker_version: 2)
  end

  it "properly formats yabeda labels" do
    expect(described_class.new(item_class: InboxItem, worker_name: worker_name, bucket: bucket, ids: ids).yabeda_labels).to eq(name: "inbox_item", type: :inbox, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: OutboxItem, worker_name: worker_name, bucket: bucket, ids: ids).yabeda_labels).to eq(name: "outbox_item", type: :outbox, worker_name: "worker", worker_version: 2)
    expect(described_class.new(item_class: Combined::OutboxItem, worker_name: worker_name, bucket: bucket, ids: ids).yabeda_labels).to eq(name: "combined-outbox_item", type: :outbox, worker_name: "worker", worker_version: 2)
  end

  it "properly converts to hash" do
    expect(described_class.new(item_class: InboxItem, worker_name: worker_name, bucket: bucket, ids: ids).to_h)
      .to eq(
        item_class: InboxItem, worker_name: "worker", worker_version: 2, bucket: 0, ids: [0, 1],
        resource_key: "inbox_item:0", resource_path: "sbmt:outbox:worker:inbox_item:0",
        log_tags: {box_name: "inbox_item", bucket: 0, box_type: :inbox, worker_name: "worker", worker_version: 2},
        yabeda_labels: {name: "inbox_item", type: :inbox, worker_name: "worker", worker_version: 2}
      )
  end
end
