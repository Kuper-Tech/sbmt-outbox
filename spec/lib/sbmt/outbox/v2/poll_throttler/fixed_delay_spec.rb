# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/fixed_delay"

describe Sbmt::Outbox::V2::PollThrottler::FixedDelay do
  let(:delay) { 0.1 }
  let(:throttler) { described_class.new(delay: delay) }
  let(:task) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  it "waits if task is PROCESSED" do
    expect(throttler).to receive(:sleep).with(delay)

    expect { throttler.call(0, task, Sbmt::Outbox::V2::ThreadPool::PROCESSED) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "throttle", throttler: "Sbmt::Outbox::V2::PollThrottler::FixedDelay", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::FixedDelay", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end

  it "does not wait if task is not PROCESSED" do
    expect(throttler).not_to receive(:sleep)

    expect { throttler.call(0, task, Sbmt::Outbox::V2::ThreadPool::SKIPPED) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "skip", throttler: "Sbmt::Outbox::V2::PollThrottler::FixedDelay", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::FixedDelay", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
  end
end
