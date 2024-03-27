# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/redis_queue_size"

describe Sbmt::Outbox::V2::PollThrottler::RedisQueueSize do
  let(:delay) { 0.1 }
  let(:min_size) { -1 }
  let(:max_size) { 10 }

  let(:task) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  let(:redis) { instance_double(RedisClient) }

  let(:throttler) { described_class.new(redis: redis, min_size: min_size, max_size: max_size, delay: delay) }

  context "when min_size is defined" do
    let(:min_size) { 5 }

    it "waits if queue size is less than min_size" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return("2")
      expect(throttler).to receive(:sleep).with(delay)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "throttle", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(2)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end

    it "does not wait if queue size is above min_size" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return("6")
      expect(throttler).not_to receive(:sleep)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(6)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end
  end

  context "when max_size is defined" do
    it "does not wait if queue size is less than max_size" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return("2")
      expect(throttler).not_to receive(:sleep)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(2)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end

    it "waits if queue size is above max_size" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return("12")
      expect(throttler).to receive(:sleep).with(delay)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "skip", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(12)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end
  end

  context "when redis command returns nil" do
    it "skips wait logic" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_return(nil)
      expect(throttler).not_to receive(:sleep)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).with(0)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end
  end

  context "when redis command raises exception" do
    it "skips wait logic" do
      allow(redis).to receive(:call).with("LLEN", task.redis_queue).and_raise("connection error")
      expect(throttler).not_to receive(:sleep)

      expect { throttler.call(0, task, nil) }
        .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "connection error", throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
        .and not_update_yabeda_gauge(Yabeda.box_worker.redis_job_queue_size)
        .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RedisQueueSize", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    end
  end
end
