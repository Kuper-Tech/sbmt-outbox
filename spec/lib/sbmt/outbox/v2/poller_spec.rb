# frozen_string_literal: true

require "sbmt/outbox/v2/poller"

# rubocop:disable RSpec/IndexedLet
describe Sbmt::Outbox::V2::Poller do
  let(:boxes) { [OutboxItem, InboxItem] }
  let(:regular_batch_size) { 2 }
  let(:retry_batch_size) { 1 }
  let(:throttler_tactic) { "noop" }

  let(:poller) do
    described_class.new(
      boxes,
      partitions_count: 2,
      lock_timeout: 1,
      threads_count: 1,
      regular_items_batch_size: regular_batch_size,
      retryable_items_batch_size: retry_batch_size,
      redis: redis,
      throttler_tactic: throttler_tactic
    )
  end

  let(:redis) { instance_double(RedisClient) }

  before { allow(redis).to receive(:pipelined).and_yield(redis) }

  context "when initialized" do
    it "properly partitions items and builds task queue" do
      task_queue = poller.send(:queue)

      tasks = []
      while task_queue.size > 0
        tasks << task_queue.pop.to_h
      end

      expect(tasks.size).to eq(boxes.count * 2)
      expect(tasks).to contain_exactly(
        hash_including(item_class: OutboxItem, partition: 0, buckets: [0, 2], resource_key: "outbox_item:0", resource_path: "sbmt:outbox:poller:outbox_item:0", redis_queue: "outbox_item:job_queue", worker_name: "poller", worker_version: 2),
        hash_including(item_class: OutboxItem, partition: 1, buckets: [1, 3], resource_key: "outbox_item:1", resource_path: "sbmt:outbox:poller:outbox_item:1", redis_queue: "outbox_item:job_queue", worker_name: "poller", worker_version: 2),
        hash_including(item_class: InboxItem, partition: 0, buckets: [0, 2], resource_key: "inbox_item:0", resource_path: "sbmt:outbox:poller:inbox_item:0", redis_queue: "inbox_item:job_queue", worker_name: "poller", worker_version: 2),
        hash_including(item_class: InboxItem, partition: 1, buckets: [1, 3], resource_key: "inbox_item:1", resource_path: "sbmt:outbox:poller:inbox_item:1", redis_queue: "inbox_item:job_queue", worker_name: "poller", worker_version: 2)
      )
    end
  end

  describe "#process_task" do
    let(:task) do
      Sbmt::Outbox::V2::Tasks::Poll.new(
        item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
      )
    end

    before { allow(poller.send(:thread_pool)).to receive(:start).and_yield(0, task) }

    it "properly acquires lock per task" do
      expect(poller.send(:lock_manager)).to receive(:lock)
        .with("sbmt:outbox:poller:inbox_item:0:lock", 1000)

      expect(poller.start).to be(Sbmt::Outbox::V2::ThreadPool::PROCESSED)
    end

    it "returns SKIPPED if lock is not acquired" do
      expect(poller.send(:lock_manager)).to receive(:lock).and_yield(nil)

      expect(poller.start).to be(Sbmt::Outbox::V2::ThreadPool::SKIPPED)
    end

    context "when default poll tactic is used" do
      let(:throttler_tactic) { "default" }

      it "throttles processing if redis queue is oversized" do
        expect(redis).to receive(:call).with("LLEN", "inbox_item:job_queue").and_return(200)
        expect(poller.send(:lock_manager)).to receive(:lock).with("sbmt:outbox:poller:inbox_item:0:lock", 1000)

        expect(poller.start).to be(Sbmt::Outbox::V2::ThreadPool::PROCESSED)
      end

      it "does not throttle processing if redis queue is not oversized" do
        expect(redis).to receive(:call).with("LLEN", "inbox_item:job_queue").and_return(0)
        expect(poller.send(:lock_manager)).to receive(:lock).with("sbmt:outbox:poller:inbox_item:0:lock", 1000)

        expect(poller.start).to be(Sbmt::Outbox::V2::ThreadPool::PROCESSED)
      end
    end

    context "when pushing to redis job queue" do
      let(:freeze_time) { Time.current }

      around { |ex| travel_to(freeze_time, &ex) }

      context "when no pending items in buckets" do
        let(:regular_batch_size) { 1 }

        let!(:item1) { create(:inbox_item, bucket: 1) }
        let!(:item2) { create(:inbox_item, bucket: 3) }

        it "returns no data" do
          expect(redis).not_to receive(:call)

          expect { poller.process_task(0, task) }
            .to measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2)
            .and not_increment_yabeda_counter(Yabeda.box_worker.job_items_counter)
            .and increment_yabeda_counter(Yabeda.box_worker.batches_per_poll_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(1)
            .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
        end
      end

      context "when items are only regular" do
        let(:regular_batch_size) { 3 }
        let(:retry_batch_size) { 1 }

        # i.e. max_batch_size = 3, max_buffer_size = 4
        # so it makes 1 batch (sql) poll request to fill regular_batch_size

        let!(:item1_1) { create(:inbox_item, bucket: 0) }
        let!(:item1_2) { create(:inbox_item, bucket: 0) }
        let!(:item2) { create(:inbox_item, bucket: 1) }
        let!(:item3) { create(:inbox_item, bucket: 2) }

        it "polls only regular items" do
          expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{freeze_time.to_i}:#{item1_1.id},#{item1_2.id}")
          expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "2:#{freeze_time.to_i}:#{item3.id}")

          expect { poller.process_task(0, task) }
            .to measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2)
            .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(3)
            .and increment_yabeda_counter(Yabeda.box_worker.batches_per_poll_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(1)
            .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
        end
      end

      context "when items are mostly retryable" do
        let(:regular_batch_size) { 1 }
        let(:retry_batch_size) { 1 }

        # i.e. max_batch_size = 1, max_buffer_size = 2
        # so it makes 2 batch (sql) poll requests
        #   1: fills buffer with 1 retryable item and skips 2nd retryable item, because retry_batch_size = 1 is already hit
        #   2: fills buffer with 1 regular item

        let!(:item1_1) { create(:inbox_item, bucket: 0, errors_count: 1) }
        let!(:item1_2) { create(:inbox_item, bucket: 0, errors_count: 1) }
        let!(:item2) { create(:inbox_item, bucket: 1, errors_count: 1) }
        let!(:item3) { create(:inbox_item, bucket: 2) }

        it "polls more batches to fill regular items buffer limit" do
          expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{freeze_time.to_i}:#{item1_1.id}")
          expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "2:#{freeze_time.to_i}:#{item3.id}")

          expect { poller.process_task(0, task) }
            .to measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2)
            .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(2)
            .and increment_yabeda_counter(Yabeda.box_worker.batches_per_poll_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(2)
            .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
        end
      end

      context "when items are mixed" do
        let(:retry_batch_size) { 1 }
        let(:regular_batch_size) { 1 }

        # i.e. max_batch_size = 1, max_buffer_size = 2
        # so it makes 1 batch (sql) poll request to fill regular_batch_size and stops
        # because regular items have priority over retryable ones
        # and the rest retryable items will be polled later in the next poll

        let!(:item1) { create(:inbox_item, bucket: 0) }
        let!(:item2) { create(:inbox_item, bucket: 1, errors_count: 1) }
        let!(:item3) { create(:inbox_item, bucket: 2, errors_count: 1) }

        it "stops if regular buffer limit is full" do
          expect(redis).to receive(:call).with("LPUSH", "inbox_item:job_queue", "0:#{freeze_time.to_i}:#{item1.id}")

          expect { poller.process_task(0, task) }
            .to measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2)
            .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(1)
            .and increment_yabeda_counter(Yabeda.box_worker.batches_per_poll_counter).with_tags(name: "inbox_item", partition: 0, type: :inbox, worker_name: "poller", worker_version: 2).by(1)
            .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
        end
      end
    end
  end
end
# rubocop:enable RSpec/IndexedLet
