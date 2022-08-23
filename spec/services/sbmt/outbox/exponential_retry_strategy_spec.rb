# frozen_string_literal: true

describe Sbmt::Outbox::ExponentialRetryStrategy do
  subject(:result) { described_class.new(**attributes).call(errors_count, last_processed_at) }

  let(:attributes) do
    {
      minimal_interval: 10,
      maximal_elapsed_time: 10 * 60,
      multiplier: 2
    }
  end
  let(:errors_count) { 0 }
  let(:last_processed_at) { Time.zone.now }

  context "when the next processing time is greater than the current time" do
    it "return false" do
      expect(result).to be(false)
    end
  end

  context "when the next processing time is less than the current time" do
    let(:last_processed_at) { 1.hour.ago }

    it "return true" do
      expect(result).to be(true)
    end
  end
end
