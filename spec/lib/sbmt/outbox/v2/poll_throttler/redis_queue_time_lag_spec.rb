# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/redis_queue_time_lag"

describe Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag do
  let(:delay) { 0.1 }
  let(:min_lag) { 5 }

  let(:task) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  let(:redis) { instance_double(RedisClient) }

  let(:throttler) { described_class.new(redis: redis, min_lag: min_lag, delay: delay) }

  it "does not wait if lag is above min_lag" do
    allow(redis).to receive(:call).with("LINDEX", task.redis_queue, -1).and_return("0:#{Time.current.to_i - 10}:1,2,3")
    expect(throttler).not_to receive(:sleep)

    expect { throttler.call(0, task, nil) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_time_lag).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(10)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end

  it "waits if lag is less than min_lag" do
    allow(redis).to receive(:call).with("LINDEX", task.redis_queue, -1).and_return("0:#{Time.current.to_i - 2}:1,2,3")
    expect(throttler).to receive(:sleep).with(delay)

    expect { throttler.call(0, task, nil) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "skip", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_time_lag).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(2)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end

  it "skips wait logic if redis command returns nil" do
    allow(redis).to receive(:call).with("LINDEX", task.redis_queue, -1).and_return(nil)
    expect(throttler).not_to receive(:sleep)

    expect { throttler.call(0, task, nil) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and not_update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_time_lag).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueTimeLag", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end
end
