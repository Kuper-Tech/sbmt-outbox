# frozen_string_literal: true

require "sbmt/outbox/v2/worker"

describe Sbmt::Outbox::V2::Worker do
  let(:boxes) { [OutboxItem] }
  let(:poll_tactic) { "aggressive" }
  let(:processor_concurrency) { 1 }
  let(:poller_partitions_count) { 1 }
  let(:poller_threads_count) { 1 }

  let!(:worker) do
    described_class.new(
      boxes: boxes,
      poll_tactic: poll_tactic,
      processor_concurrency: processor_concurrency,
      poller_partitions_count: poller_partitions_count,
      poller_threads_count: poller_threads_count
    )
  end

  let(:failing_transport) do
    lambda { |_item, _payload| raise StandardError }
  end
  let(:transport) do
    lambda { |_item, _payload| true }
  end

  around do |spec|
    spec.run
    worker.stop
  end

  context "when initialized" do
    it "passes readiness check" do
      worker.start_async

      expect(worker).to be_ready
    end
  end

  context "when processing error occurred" do
    let!(:first_failing) { create(:outbox_item, bucket: 0) }
    let!(:second_failing) { create(:outbox_item, bucket: 1) }
    let!(:first_successful) { create(:inbox_item, bucket: 0) }
    let!(:second_successful) { create(:inbox_item, bucket: 1) }

    let(:processor_concurrency) { 2 }
    let(:poller_partitions_count) { 1 }
    let(:poller_threads_count) { 2 }
    let(:boxes) { [OutboxItem, InboxItem] }

    before do
      allow_any_instance_of(Sbmt::Outbox::OutboxItemConfig).to receive_messages(
        max_retries: 1,
        retry_strategies: [Sbmt::Outbox::RetryStrategies::NoDelay],
        transports: {_all_: [failing_transport]}
      )
      allow_any_instance_of(Sbmt::Outbox::InboxItemConfig).to receive_messages(
        transports: {_all_: [transport]}
      )
    end

    it "concurrently retries processing" do
      expect do
        worker.start_async
        sleep(2)
      end.to change(OutboxItem.failed, :count).from(0).to(2)
        .and change(InboxItem.delivered, :count).from(0).to(2)

      expect(first_failing.reload.errors_count).to eq(2)
      expect(second_failing.reload.errors_count).to eq(2)
      expect(first_successful.reload.errors_count).to eq(0)
      expect(second_successful.reload.errors_count).to eq(0)
    end
  end

  context "with poller concurrency" do
    let!(:first) { create(:inbox_item, bucket: 0) }
    let!(:second) { create(:inbox_item, bucket: 0) }
    let!(:third) { create(:inbox_item, bucket: 1) }
    let!(:forth) { create(:inbox_item, bucket: 1) }

    let(:processor_concurrency) { 2 }
    let(:poller_partitions_count) { 2 }
    let(:poller_threads_count) { 2 }
    let(:boxes) { [InboxItem] }

    before do
      allow_any_instance_of(Sbmt::Outbox::InboxItemConfig).to receive_messages(
        transports: {_all_: [transport]}
      )
    end

    it "successfully processes items" do
      expect do
        worker.start_async
        sleep(2)
      end.to change(InboxItem.delivered, :count).from(0).to(4)
    end
  end

  context "with default poll tactic" do
    let!(:item) { create(:outbox_item, bucket: 0) }
    let(:poll_tactic) { "default" }

    before do
      allow_any_instance_of(Sbmt::Outbox::OutboxItemConfig).to receive_messages(
        transports: {_all_: [transport]}
      )
    end

    it "successfully processes item" do
      expect do
        worker.start_async
        sleep(2)
      end.to change(OutboxItem.delivered, :count).from(0).to(1)
    end
  end

  context "with low-priority poll tactic" do
    let!(:item) { create(:outbox_item, bucket: 0) }
    let(:poll_tactic) { "low-priority" }

    before do
      allow_any_instance_of(Sbmt::Outbox::OutboxItemConfig).to receive_messages(
        transports: {_all_: [transport]}
      )
    end

    it "successfully processes item" do
      expect do
        worker.start_async
        sleep(2)
      end.to change(OutboxItem.delivered, :count).from(0).to(1)
    end
  end
end
