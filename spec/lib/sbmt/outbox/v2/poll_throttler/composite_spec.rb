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
end
