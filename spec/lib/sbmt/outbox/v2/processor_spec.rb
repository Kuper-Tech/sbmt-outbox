# frozen_string_literal: true

require "sbmt/outbox/v2/processor"

# rubocop:disable RSpec/IndexedLet
describe Sbmt::Outbox::V2::Processor do
  let(:boxes) { [OutboxItem, InboxItem] }

  let(:processor) do
    described_class.new(
      boxes,
      lock_timeout: 1,
      threads_count: 1,
      redis: redis
    )
  end

  let(:redis) { instance_double(RedisClient) }

  context "when initialized" do
    it "properly builds task queue" do
      task_queue = processor.send(:queue)

      tasks = []
      while task_queue.size > 0
        tasks << task_queue.pop.to_h
      end

      expect(tasks.size).to eq(boxes.count)
      expect(tasks).to contain_exactly(
        hash_including(item_class: OutboxItem, worker_name: "processor", worker_version: 2),
        hash_including(item_class: InboxItem, worker_name: "processor", worker_version: 2)
      )
    end
  end

  describe "#process_task" do
    let(:task) do
      Sbmt::Outbox::V2::Tasks::Base.new(item_class: InboxItem, worker_name: "processor")
    end

    before do
      allow(processor.send(:thread_pool)).to receive(:start).and_yield(0, task)
      allow(redis).to receive(:read_timeout).and_return(1)
    end

    context "when redis job queue has pending job" do
      let!(:item1) { create(:inbox_item, bucket: 0) }
      let!(:item2) { create(:inbox_item, bucket: 0) }

      before do
        allow(redis).to receive(:blocking_call).with(1.1, "BRPOP", "inbox_item:job_queue", 0.1).and_return(%W[inbox_item:job_queue 0:#{Time.current.to_i}:#{item1.id},#{item2.id}])
      end

      it "fetches job from redis, acquires lock and processes it" do
        expect(processor.send(:lock_manager)).to receive(:lock)
          .with("sbmt:outbox:processor:inbox_item:0:lock", 1000)
          .and_yield(task)

        expect { processor.start }.to change(InboxItem.delivered, :count).from(0).to(2)
          .and measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2)
          .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2).by(2)
          .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
          .and increment_yabeda_counter(Yabeda.outbox.sent_counter).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2).by(2)
          .and update_yabeda_gauge(Yabeda.outbox.last_sent_event_id).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2)
          .and measure_yabeda_histogram(Yabeda.outbox.process_latency).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2)
          .and increment_yabeda_counter(Yabeda.outbox.error_counter).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2).by(0)
          .and increment_yabeda_counter(Yabeda.outbox.retry_counter).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2).by(0)
          .and increment_yabeda_counter(Yabeda.outbox.discarded_counter).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2).by(0)
          .and increment_yabeda_counter(Yabeda.outbox.fetch_error_counter).with_tags(name: "inbox_item", type: :inbox, owner: nil, partition: 0, worker_version: 2).by(0)
      end

      it "skips job if lock is already being held by other thread" do
        expect(processor.send(:lock_manager)).to receive(:lock)
          .with("sbmt:outbox:processor:inbox_item:0:lock", 1000)
          .and_yield(nil)

        expect(processor.start).to be(Sbmt::Outbox::V2::ThreadPool::SKIPPED)
      end

      context "when use option strict_order" do
        context "when strict_order is true" do
          before do
            allow(task.item_class).to receive(:config).and_return(OpenStruct.new(strict_order: true))
          end

          it "stops processing on failure" do
            expect(processor.send(:lock_manager)).to receive(:lock)
              .with("sbmt:outbox:processor:inbox_item:0:lock", 1000)
              .and_yield(task)

            allow(Sbmt::Outbox::ProcessItem).to receive(:call).with(any_args).and_return(OpenStruct.new(failure?: true))

            expect { processor.start }.to not_change(InboxItem.delivered, :count)
              .and measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2)
              .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2).by(1)
              .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.sent_counter)
              .and not_update_yabeda_gauge(Yabeda.outbox.last_sent_event_id)
              .and not_measure_yabeda_histogram(Yabeda.outbox.process_latency)
              .and not_increment_yabeda_counter(Yabeda.outbox.error_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.retry_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.discarded_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.fetch_error_counter)
          end
        end

        context "when strict_order is false" do
          it "continues processing on failure" do
            expect(processor.send(:lock_manager)).to receive(:lock)
              .with("sbmt:outbox:processor:inbox_item:0:lock", 1000)
              .and_yield(task)

            allow(Sbmt::Outbox::ProcessItem).to receive(:call).with(any_args).and_return(OpenStruct.new(failure?: true))

            expect { processor.start }.to not_change(InboxItem.delivered, :count)
              .and measure_yabeda_histogram(Yabeda.box_worker.item_execution_runtime).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2)
              .and increment_yabeda_counter(Yabeda.box_worker.job_items_counter).with_tags(name: "inbox_item", type: :inbox, worker_name: "processor", worker_version: 2).by(2)
              .and not_increment_yabeda_counter(Yabeda.box_worker.job_timeout_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.sent_counter)
              .and not_update_yabeda_gauge(Yabeda.outbox.last_sent_event_id)
              .and not_measure_yabeda_histogram(Yabeda.outbox.process_latency)
              .and not_increment_yabeda_counter(Yabeda.outbox.error_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.retry_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.discarded_counter)
              .and not_increment_yabeda_counter(Yabeda.outbox.fetch_error_counter)
          end
        end
      end
    end

    context "when redis job queue is empty" do
      it "waits for 1 sec and skips task" do
        expect(redis).to receive(:blocking_call).with(1.1, "BRPOP", "inbox_item:job_queue", 0.1).and_return(nil)
        expect(processor.send(:lock_manager)).not_to receive(:lock)

        expect(processor.start).to be(Sbmt::Outbox::V2::ThreadPool::SKIPPED)
      end
    end
  end
end
# rubocop:enable RSpec/IndexedLet
