# frozen_string_literal: true

require "sbmt/outbox/worker"

describe Sbmt::Outbox::Worker do
  let(:worker) do
    described_class.new(
      boxes: boxes,
      concurrency: concurrency
    )
  end

  around do |block|
    Timeout.timeout(15, &block)
  rescue Timeout::Error
    worker.stop
  end

  describe "threads concurrency" do
    let(:boxes) { [OutboxItem, InboxItem] }
    let(:concurrency) { 2 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @outbox_item_1 = Fabricate(:outbox_item, event_key: 1, bucket: 0)
      @outbox_item_2 = Fabricate(:outbox_item, event_key: 2, bucket: 1)
      @inbox_item_3 = Fabricate(:inbox_item, event_key: 3, bucket: 0)
      @inbox_item_4 = Fabricate(:inbox_item, event_key: 4, bucket: 1)
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
        sleep 3
        thread_1 = thread_pool.worker_number
        processed << @outbox_item_1.event_key
        processed_by_thread[thread_pool.worker_number] << @outbox_item_1.event_key
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @outbox_item_2.id) do |_klass, _id|
        sleep 5
        thread_2 = thread_pool.worker_number
        processed << @outbox_item_2.event_key
        processed_by_thread[thread_pool.worker_number] << @outbox_item_2.event_key
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(InboxItem, @inbox_item_3.id) do |_klass, _id|
        processed << @inbox_item_3.event_key
        processed_by_thread[thread_pool.worker_number] << @inbox_item_3.event_key
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(InboxItem, @inbox_item_4.id) do |_klass, _id|
        worker.stop

        processed << @inbox_item_4.event_key
        processed_by_thread[thread_pool.worker_number] << @inbox_item_4.event_key
      end

      worker.start

      expect(processed).to eq [1, 3, 4, 2]
      expect(processed_by_thread[thread_1]).to eq [1, 3, 4]
      expect(processed_by_thread[thread_2]).to eq [2]
    end
  end

  describe "cutoff timeout" do
    let(:boxes) { [OutboxItem] }
    let(:concurrency) { 1 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @item_1 = Fabricate(:outbox_item, bucket: 0)
      @item_2 = Fabricate(:outbox_item, bucket: 0)
    end

    after(:context) do
      @item_1.destroy
      @item_2.destroy
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "requeues job to start processing from last id" do
      processed = []

      allow(worker).to receive(:cutoff_timeout).and_return(2)

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @item_1.id) do |_klass, _id|
        sleep 3
        processed << @item_1
      end

      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @item_2.id) do |_klass, _id|
        processed << @item_2
        worker.stop
      end

      worker.start

      expect(processed).to eq [@item_1, @item_2]
    end
  end

  describe "error while processing" do
    let(:boxes) { [OutboxItem] }
    let(:concurrency) { 1 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @item_1 = Fabricate(:outbox_item)
    end

    after(:context) do
      @item_1.destroy
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "does not fail" do
      expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(OutboxItem, @item_1.id).once do |_klass, _id|
        worker.stop
        raise "test error"
      end

      expect(Sbmt::Outbox.logger).to receive(:log_error)
        .with(/test error/, hash_including(:backtrace))
        .and_call_original

      worker.start
    end
  end
end
