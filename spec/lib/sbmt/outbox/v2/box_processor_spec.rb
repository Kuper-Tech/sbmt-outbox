# frozen_string_literal: true

require "sbmt/outbox/v2/box_processor"

describe Sbmt::Outbox::V2::BoxProcessor do
  let(:boxes) { [OutboxItem, InboxItem] }
  let(:threads_count) { 1 }

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
      threads_count: threads_count
    )
  end

  context "when initialized" do
    it "properly partitions items and builds task queue" do
      task_queue = processor.send(:queue)

      tasks = []
      while task_queue.size > 0
        tasks << task_queue.pop.to_h
      end

      expect(tasks.size).to eq(boxes.count)
      expect(tasks).to contain_exactly(
        hash_including(item_class: OutboxItem, worker_name: "abstract_worker", worker_version: 2),
        hash_including(item_class: InboxItem, worker_name: "abstract_worker", worker_version: 2)
      )
    end
  end

  context "with processed task" do
    let(:task) do
      Sbmt::Outbox::V2::Tasks::Base.new(item_class: InboxItem, worker_name: "abstract_worker")
    end

    before { allow(processor.send(:thread_pool)).to receive(:start).and_yield(0, task) }

    it "logs task tags" do
      expect(Sbmt::Outbox.logger).to receive(:with_tags).with(**task.log_tags)

      expect { processor.start }
        .to increment_yabeda_counter(Yabeda.box_worker.job_counter).with_tags(name: "inbox_item", state: "processed", type: :inbox, worker_name: "abstract_worker", worker_version: 2).by(1)
        .and measure_yabeda_histogram(Yabeda.box_worker.job_execution_runtime).with_tags(name: "inbox_item", type: :inbox, worker_name: "abstract_worker", worker_version: 2)
    end
  end
end
