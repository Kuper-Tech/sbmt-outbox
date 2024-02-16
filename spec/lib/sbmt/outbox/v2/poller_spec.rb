# frozen_string_literal: true

require "sbmt/outbox/v2/poller"

# rubocop:disable RSpec/IndexedLet
describe Sbmt::Outbox::V2::Poller do
  let(:boxes) { [OutboxItem, InboxItem] }
  let(:regular_batch_size) { 2 }
  let(:retry_batch_size) { 1 }

  let(:poller) do
    described_class.new(
      boxes,
      partitions_count: 2,
      threads_count: 1,
      regular_items_batch_size: regular_batch_size,
      retryable_items_batch_size: retry_batch_size
    )
  end

  let(:redis) { instance_double(RedisClient) }

  before do
    allow(poller.send(:redis)).to receive(:pipelined).and_yield(redis)
  end

  describe "#process_task" do
    let(:task) do
      Sbmt::Outbox::V2::PartitionedBoxProcessor::Task.new(
        item_class: InboxItem, partition: 0, buckets: [0, 2],
        resource_key: "inbox_item:0", resource_path: "sbmt:outbox:abstract_worker:inbox_item:0"
      )
    end

    context "when no pending items in buckets" do
      let(:regular_batch_size) { 1 }

      let!(:item1) { create(:inbox_item, bucket: 1) }
      let!(:item2) { create(:inbox_item, bucket: 3) }

      it "returns no data" do
        expect(redis).not_to receive(:call)

        poller.process_task(0, task)
      end
    end

    context "when items are only regular" do
      let(:retry_batch_size) { 1 }
      let(:regular_batch_size) { 3 }

      let!(:item1_1) { create(:inbox_item, bucket: 0) }
      let!(:item1_2) { create(:inbox_item, bucket: 0) }
      let!(:item2) { create(:inbox_item, bucket: 1) }
      let!(:item3) { create(:inbox_item, bucket: 2) }

      it "polls only regular items" do
        expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{item1_1.id},#{item1_2.id}")
        expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "2:#{item3.id}")

        poller.process_task(0, task)
      end
    end

    context "when items are mostly retryable" do
      let(:retry_batch_size) { 1 }
      let(:regular_batch_size) { 1 }

      let!(:item1_1) { create(:inbox_item, bucket: 0, processed_at: Time.current) }
      let!(:item1_2) { create(:inbox_item, bucket: 0, processed_at: Time.current) }
      let!(:item2) { create(:inbox_item, bucket: 1, processed_at: Time.current) }
      let!(:item3) { create(:inbox_item, bucket: 2) }

      it "polls more batches to fill regular items buffer limit" do
        expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{item1_1.id}")
        expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "2:#{item3.id}")

        poller.process_task(0, task)
      end
    end

    context "when items are mixed" do
      let(:retry_batch_size) { 1 }
      let(:regular_batch_size) { 1 }

      let!(:item1) { create(:inbox_item, bucket: 0) }
      let!(:item2) { create(:inbox_item, bucket: 1, processed_at: Time.current) }
      let!(:item3) { create(:inbox_item, bucket: 2, processed_at: Time.current) }

      it "stops if regular buffer limit is full" do
        expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{item1.id}")

        poller.process_task(0, task)
      end
    end
  end
end
# rubocop:enable RSpec/IndexedLet
