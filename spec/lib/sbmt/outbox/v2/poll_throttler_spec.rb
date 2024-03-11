# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler"

describe Sbmt::Outbox::V2::PollThrottler do
  let(:redis) { instance_double(RedisClient) }
  let(:tactic) { nil }
  let(:poller_config) { {} }

  let(:build) { described_class.build(tactic, redis, poller_config) }

  describe "#build" do
    context "with noop throttler" do
      let(:tactic) { "noop" }

      it "properly builds throttler" do
        expect(build).to be_an_instance_of(described_class::Noop)
      end
    end

    context "with default throttler" do
      let(:tactic) { "default" }
      let(:poller_config) { Sbmt::Outbox.poller_config }

      it "properly builds throttler" do
        throttler = build

        expect(throttler).to be_an_instance_of(described_class::Composite)
        expect(throttler.throttlers.count).to eq(2)
        expect(throttler.throttlers[0]).to be_an_instance_of(described_class::RedisQueueSize)
        expect(throttler.throttlers[1]).to be_an_instance_of(described_class::RateLimited)
      end
    end

    context "with low-priority throttler" do
      let(:tactic) { "low-priority" }
      let(:poller_config) { Sbmt::Outbox.poller_config }

      it "properly builds throttler" do
        throttler = build

        expect(throttler).to be_an_instance_of(described_class::Composite)
        expect(throttler.throttlers.count).to eq(3)
        expect(throttler.throttlers[0]).to be_an_instance_of(described_class::RedisQueueSize)
        expect(throttler.throttlers[1]).to be_an_instance_of(described_class::RedisQueueTimeLag)
        expect(throttler.throttlers[2]).to be_an_instance_of(described_class::RateLimited)
      end
    end

    context "with aggressive throttler" do
      let(:tactic) { "aggressive" }
      let(:poller_config) { Sbmt::Outbox.poller_config }

      it "properly builds throttler" do
        throttler = build

        expect(throttler).to be_an_instance_of(described_class::RedisQueueSize)
      end
    end

    context "with unknown throttler" do
      let(:tactic) { "awesome-tactic" }

      it "properly builds throttler" do
        expect { build }.to raise_error(/invalid poller poll tactic/)
      end
    end
  end
end
