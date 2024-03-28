# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/rate_limited"

describe Sbmt::Outbox::V2::PollThrottler::RateLimited do
  let(:limit) { 60 }
  let(:interval) { 60 }

  let(:throttler) { described_class.new(limit: limit, interval: interval) }
  let(:task_inbox) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end
  let(:task_outbox) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: OutboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  it "uses different queues for item classes" do
    expect do
      throttler.call(0, task_inbox, Sbmt::Outbox::V2::ThreadPool::PROCESSED)
      throttler.call(0, task_outbox, Sbmt::Outbox::V2::ThreadPool::PROCESSED)
      throttler.call(0, task_inbox, Sbmt::Outbox::V2::ThreadPool::PROCESSED)
      throttler.call(0, task_outbox, Sbmt::Outbox::V2::ThreadPool::PROCESSED)
    end.to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "throttle", throttler: "Sbmt::Outbox::V2::PollThrottler::RateLimited", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(2)
      .and increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "throttle", throttler: "Sbmt::Outbox::V2::PollThrottler::RateLimited", name: "outbox_item", type: :outbox, worker_name: "poller", worker_version: 2).by(2)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RateLimited", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::RateLimited", name: "outbox_item", type: :outbox, worker_name: "poller", worker_version: 2)

    expect(throttler.queues.count).to eq(2)
  end
end
