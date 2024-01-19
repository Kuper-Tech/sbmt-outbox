# frozen_string_literal: true

describe Sbmt::Outbox::RetryStrategies::ExponentialBackoff do
  subject(:result) { described_class.call(outbox_item) }

  let(:outbox_item) { create(:outbox_item, processed_at: processed_at) }

  let(:processed_at) { Time.zone.now }

  context "when the next processing time is greater than the current time" do
    it "skips processing" do
      expect(result).to be_failure
      expect(result.failure).to eq :skip_processing
    end
  end

  context "when the next processing time is less than the current time" do
    let(:processed_at) { 1.hour.ago }

    it "allows processing" do
      expect(result).to be_success
    end
  end
end
