# frozen_string_literal: true

require "sbmt/outbox/v2/partitioned_box_processor"

describe Sbmt::Outbox::V2::PartitionedBoxProcessor do
  let(:boxes) { [OutboxItem, InboxItem] }
  let(:partitions_count) { 2 }
  let(:threads_count) { 1 }
  let(:lock_timeout) { 1 }

  let(:processor_klass) do
    Class.new(described_class) do
      def process_task(worker_number, task)
        # noop
      end
    end
  end

  let(:processor) do
    processor_klass.new(
      boxes: boxes,
      partitions_count: partitions_count,
      threads_count: threads_count,
      lock_timeout: lock_timeout
    )
  end

  context "when initialized" do
    it "properly partitions items and builds task queue" do
      task_queue = processor.send(:queue)

      tasks = []
      while task_queue.size > 0
        tasks << task_queue.pop.to_h
      end

      expect(tasks.size).to eq(boxes.count * partitions_count)
      expect(tasks).to contain_exactly(
        {item_class: OutboxItem, partition: 0, buckets: [0, 2], resource_key: "outbox_item:0", resource_path: "sbmt:outbox:abstract_worker:outbox_item:0"},
        {item_class: OutboxItem, partition: 1, buckets: [1, 3], resource_key: "outbox_item:1", resource_path: "sbmt:outbox:abstract_worker:outbox_item:1"},
        {item_class: InboxItem, partition: 0, buckets: [0, 2], resource_key: "inbox_item:0", resource_path: "sbmt:outbox:abstract_worker:inbox_item:0"},
        {item_class: InboxItem, partition: 1, buckets: [1, 3], resource_key: "inbox_item:1", resource_path: "sbmt:outbox:abstract_worker:inbox_item:1"}
      )
    end
  end

  context "with processed task" do
    let(:task) do
      Sbmt::Outbox::V2::PartitionedBoxProcessor::Task.new(
        item_class: InboxItem, partition: 0, buckets: [0, 2],
        resource_key: "inbox_item:0", resource_path: "sbmt:outbox:abstract_worker:inbox_item:0"
      )
    end

    before { allow(processor.send(:thread_pool)).to receive(:start).and_yield(0, task) }

    it "properly acquires lock per task" do
      expect(processor.send(:lock_manager)).to receive(:lock)
        .with("sbmt:outbox:abstract_worker:inbox_item:0:lock", lock_timeout * 1000)
        .and_yield(true)

      expect(processor.start).to be(Sbmt::Outbox::V2::ThreadPool::PROCESSED)
    end

    it "returns SKIPPED if lock is not acquired" do
      expect(processor.send(:lock_manager)).to receive(:lock).and_yield(false)

      expect(processor.start).to be(Sbmt::Outbox::V2::ThreadPool::SKIPPED)
    end

    it "logs task tags" do
      expect(processor.send(:lock_manager)).to receive(:lock).and_yield(true)
      expect(Sbmt::Outbox.logger).to receive(:with_tags).with(**task.log_tags)

      processor.start
    end
  end
end
