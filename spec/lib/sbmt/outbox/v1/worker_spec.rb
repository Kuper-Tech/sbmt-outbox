# frozen_string_literal: true

require "sbmt/outbox/v1/worker"

# rubocop:disable RSpec/InstanceVariable
describe Sbmt::Outbox::V1::Worker do
  let(:worker) do
    described_class.new(
      boxes: boxes,
      concurrency: concurrency
    )
  end
  let!(:processed_info) {
    {
      processed: [],
      processed_by_thread: Hash.new { |hash, key| hash[key] = [] }
    }
  }

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
      @outbox_item_1 = create(:outbox_item, event_key: 1, bucket: 0)
      @outbox_item_2 = create(:outbox_item, event_key: 2, bucket: 1)
      @inbox_item_3 = create(:inbox_item, event_key: 3, bucket: 0)
      @inbox_item_4 = create(:inbox_item, event_key: 4, bucket: 1)
    end

    after(:context) do
      @outbox_item_1.destroy!
      @outbox_item_2.destroy!
      @inbox_item_3.destroy!
      @inbox_item_4.destroy!
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "runs in expected order" do
      thread_pool = worker.send(:thread_pool)

      thread_1 = nil
      thread_2 = nil

      expect(worker).to receive(:process_job).exactly(4).times.and_call_original

      expect_to_process_item(@outbox_item_1, sleep_time: 3) do
        thread_1 = thread_pool.worker_number
      end
      expect_to_process_item(@outbox_item_2, sleep_time: 5) do
        thread_2 = thread_pool.worker_number
      end
      expect_to_process_item(@inbox_item_3)
      expect_to_process_item(@inbox_item_4) do
        worker.stop
      end

      worker.start

      expect(processed_info[:processed]).to eq [1, 3, 4, 2]
      expect(processed_info[:processed_by_thread][thread_1]).to eq [1, 3, 4]
      expect(processed_info[:processed_by_thread][thread_2]).to eq [2]
    end
  end

  describe "cutoff timeout" do
    let(:boxes) { [OutboxItem] }
    let(:concurrency) { 1 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @item_1 = create(:outbox_item, bucket: 0)
      @item_2 = create(:outbox_item, bucket: 0)
    end

    after(:context) do
      @item_1.destroy
      @item_2.destroy
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "requeues job to start processing from last id" do
      allow(worker).to receive(:cutoff_timeout).and_return(2)

      expect_to_process_item(@item_1, sleep_time: 3)
      expect_to_process_item(@item_2, sleep_time: 3) do
        worker.stop
      end

      worker.start

      expect(processed_info[:processed]).to eq [@item_1.event_key, @item_2.event_key]
    end
  end

  describe "error while processing" do
    let(:boxes) { [OutboxItem] }
    let(:concurrency) { 1 }

    # TODO: [Rails 5.1] Database transactions are shared between test threads
    # rubocop:disable RSpec/BeforeAfterAll
    before(:context) do
      @item_1 = create(:outbox_item)
    end

    after(:context) do
      @item_1.destroy
    end
    # rubocop:enable RSpec/BeforeAfterAll

    it "does not fail" do
      expect_to_process_item(@item_1, sleep_time: 3) do
        worker.stop
        raise "test error"
      end

      expect(Sbmt::Outbox.logger).to receive(:log_error)
        .with(/test error/, hash_including(:backtrace))
        .and_call_original

      worker.start
    end
  end

  def expect_to_process_item(item, sleep_time: nil)
    expect(Sbmt::Outbox::ProcessItem).to receive(:call).with(item.class, item.id) do |_id|
      sleep sleep_time if sleep_time
      yield if block_given?

      next unless processed_info

      processed = processed_info[:processed]
      processed_by_thread = processed_info[:processed_by_thread]

      processed_info[:processed] << item.event_key if processed
      processed_by_thread[worker.send(:thread_pool).worker_number] << item.event_key if processed_by_thread
    end
  end
end
# rubocop:enable RSpec/InstanceVariable