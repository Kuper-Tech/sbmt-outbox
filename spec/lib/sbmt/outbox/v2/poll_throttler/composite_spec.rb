# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/composite"
require "sbmt/outbox/v2/poll_throttler/rate_limited"
require "sbmt/outbox/v2/poll_throttler/redis_queue_size"

describe Sbmt::Outbox::V2::PollThrottler::Composite do
  let(:delay) { 0.1 }
  let(:redis) { instance_double(RedisClient) }

  let(:redis_throttler) { Sbmt::Outbox::V2::PollThrottler::RedisQueueSize.new(redis: redis, max_size: 10, delay: delay) }

  let(:throttler) do
    described_class.new(throttlers: [redis_throttler])
  end

  let(:task) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  it "sequentially calls throttlers" do
    expect(redis_throttler).to receive(:sleep).with(delay)
    allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return("15")

    expect(redis_throttler).to receive(:wait).and_call_original

    expect { throttler.call(0, task, Sbmt::Outbox::V2::ThreadPool::PROCESSED) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "skip", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end

  context "with return status" do
    let(:failure_throttler) { instance_double(Sbmt::Outbox::V2::PollThrottler::Base) }
    let(:skip_throttler) { instance_double(Sbmt::Outbox::V2::PollThrottler::Base) }
    let(:noop_throttler) { instance_double(Sbmt::Outbox::V2::PollThrottler::Base) }
    let(:throttle_throttler) { instance_double(Sbmt::Outbox::V2::PollThrottler::Base) }

    before do
      allow(failure_throttler).to receive(:call).and_return(Dry::Monads::Result::Failure.new("some err"))
      allow(skip_throttler).to receive(:call).and_return(Dry::Monads::Result::Success.new(Sbmt::Outbox::V2::Throttler::SKIP_STATUS))
      allow(noop_throttler).to receive(:call).and_return(Dry::Monads::Result::Success.new(Sbmt::Outbox::V2::Throttler::NOOP_STATUS))
      allow(throttle_throttler).to receive(:call).and_return(Dry::Monads::Result::Success.new(Sbmt::Outbox::V2::Throttler::THROTTLE_STATUS))
    end

    it "returns skip if present" do
      expect(described_class.new(throttlers: [
        throttle_throttler, noop_throttler, skip_throttler, failure_throttler
      ]).call(0, task, nil).value!).to eq(Sbmt::Outbox::V2::Throttler::SKIP_STATUS)
    end

    it "returns failure if present" do
      expect(described_class.new(throttlers: [
        throttle_throttler, noop_throttler, failure_throttler
      ]).call(0, task, nil).failure).to eq("some err")
    end

    it "returns throttle if present" do
      expect(described_class.new(throttlers: [
        throttle_throttler, noop_throttler
      ]).call(0, task, nil).value!).to eq(Sbmt::Outbox::V2::Throttler::THROTTLE_STATUS)
    end
  end
end
