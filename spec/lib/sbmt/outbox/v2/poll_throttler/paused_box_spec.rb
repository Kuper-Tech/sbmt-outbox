# frozen_string_literal: true

require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/poll_throttler/paused_box"

describe Sbmt::Outbox::V2::PollThrottler::PausedBox do
  let(:throttler) { described_class.new }
  let(:task) do
    Sbmt::Outbox::V2::Tasks::Poll.new(
      item_class: InboxItem, worker_name: "poller", partition: 0, buckets: [0, 2]
    )
  end

  it "noops if box is not paused" do
    allow(InboxItem.config).to receive(:polling_enabled?).and_return(true)

    result = nil
    expect { result = throttler.call(0, task, Sbmt::Outbox::V2::ThreadPool::PROCESSED) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "noop", throttler: "Sbmt::Outbox::V2::PollThrottler::PausedBox", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::PausedBox", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    expect(result.value!).to eq(Sbmt::Outbox::V2::Throttler::NOOP_STATUS)
  end

  it "skips if box is paused" do
    allow(InboxItem.config).to receive(:polling_enabled?).and_return(false)

    result = nil
    expect { result = throttler.call(0, task, Sbmt::Outbox::V2::ThreadPool::PROCESSED) }
      .to increment_yabeda_counter(Yabeda.box_worker.poll_throttling_counter).with_tags(status: "skip", throttler: "Sbmt::Outbox::V2::PollThrottler::PausedBox", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2).by(1)
      .and measure_yabeda_histogram(Yabeda.box_worker.poll_throttling_runtime).with_tags(throttler: "Sbmt::Outbox::V2::PollThrottler::PausedBox", name: "inbox_item", type: :inbox, worker_name: "poller", worker_version: 2)
    expect(result.value!).to eq(Sbmt::Outbox::V2::Throttler::SKIP_STATUS)
  end
end
