# frozen_string_literal: true

require "sbmt/outbox/worker"

describe Sbmt::Outbox::Worker do
  let(:worker) do
    described_class.new(
      boxes: boxes,
      concurrency: concurrency
    )
  end

  describe "threads concurrency" do
    let(:boxes) { {OutboxItem => 1..2, InboxItem => 3..4} }
    let(:concurrency) { 2 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @outbox_item_1 = Fabricate(:outbox_item, partition_key: 1)
      @outbox_item_2 = Fabricate(:outbox_item, partition_key: 2)
      @inbox_item_3 = Fabricate(:inbox_item, partition_key: 3)
      @inbox_item_4 = Fabricate(:inbox_item, partition_key: 4)
    end

    after(:context) do
      @outbox_item_1.destroy!
      @outbox_item_2.destroy!
      @inbox_item_3.destroy!
      @inbox_item_4.destroy!
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "runs in expected order" do
      processed = []
      processed_by_thread = Hash.new { |hash, key| hash[key] = [] }
      thread_pool = worker.send(:thread_pool)
      thread_1 = nil
      thread_2 = nil

      expect(worker).to receive(:process_job).exactly(4).times.and_call_original

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @outbox_item_1.id) do |_klass, _id|
        sleep 0.5
        thread_1 = thread_pool.worker_number
        processed << @outbox_item_1
        processed_by_thread[thread_pool.worker_number] << @outbox_item_1
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @outbox_item_2.id) do |_klass, _id|
        sleep 3
        thread_2 = thread_pool.worker_number
        processed << @outbox_item_2
        processed_by_thread[thread_pool.worker_number] << @outbox_item_2
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(InboxItem, @inbox_item_3.id) do |_klass, _id|
        sleep 0.5
        processed << @inbox_item_3
        processed_by_thread[thread_pool.worker_number] << @inbox_item_3
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(InboxItem, @inbox_item_4.id) do |_klass, _id|
        sleep 0.5
        processed << @inbox_item_4
        processed_by_thread[thread_pool.worker_number] << @inbox_item_4

        worker.stop
      end

      worker.start

      expect(processed).to eq [@outbox_item_1, @inbox_item_3, @inbox_item_4, @outbox_item_2]
      expect(processed_by_thread[thread_1]).to eq [@outbox_item_1, @inbox_item_3, @inbox_item_4]
      expect(processed_by_thread[thread_2]).to eq [@outbox_item_2]
    end
  end

  describe "cutoff timeout" do
    let(:boxes) { {OutboxItem => [1]} }
    let(:concurrency) { 1 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @item_1 = Fabricate(:outbox_item)
      @item_2 = Fabricate(:outbox_item)
    end

    after(:context) do
      @item_1.destroy
      @item_2.destroy
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "requeues job to start processing from last id" do
      processed = []

      expect(worker).to receive(:cutoff_timeout).and_return(2).twice

      expect(worker).to receive(:process_job).with(kind_of(Sbmt::Outbox::Worker::Job), 1).ordered.and_call_original

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @item_1.id) do |_klass, _id|
        puts "Go to sleep for 3 secs"
        sleep 3
        processed << @item_1
      end.ordered

      expect(worker).to receive(:process_job).with(kind_of(Sbmt::Outbox::Worker::Job), @item_2.id).ordered.and_call_original

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @item_2.id) do |_klass, _id|
        processed << @item_2
        worker.stop
      end.ordered

      worker.start

      expect(processed).to eq [@item_1, @item_2]
    end
  end
end
