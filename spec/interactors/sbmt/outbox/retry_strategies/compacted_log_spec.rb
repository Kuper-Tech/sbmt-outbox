# frozen_string_literal: true

describe Sbmt::Outbox::RetryStrategies::CompactedLog do
  subject(:result) { described_class.call(outbox_item_1) }

  let(:event_key) { 10 }
  let!(:outbox_item_1) { Fabricate(:combined_outbox_item, event_key: 10) }

  context "when there are no items ahead" do
    it { expect(result).to be_success }
  end

  context "when there are no items ahead with same key" do
    let!(:outbox_item_2) { Fabricate(:combined_outbox_item, status: :delivered, event_key: event_key + 1) }

    it { expect(result).to be_success }
  end

  context "when there are no items ahead with same event_name" do
    let!(:outbox_item_2) { Fabricate(:combined_outbox_item, status: :delivered, event_key: event_key, event_name: "some-name") }

    it { expect(result).to be_success }
  end

  context "when outbox item doesn't have event_key" do
    before do
      allow(outbox_item_1).to receive(:has_attribute?).with(:event_key).and_return(false)
    end

    it { expect(result.failure).to eq :missing_event_key }
  end

  context "when outbox item event_key is blank" do
    before do
      allow(outbox_item_1).to receive(:event_key).and_return(nil)
    end

    it { expect(result.failure).to eq :empty_event_key }
  end

  context "when next is delivered" do
    let!(:outbox_item_2) { Fabricate(:combined_outbox_item, status: :delivered, event_key: event_key) }

    it { expect(result.failure).to eq :discard_item }
  end

  context "when next is pending" do
    let!(:outbox_item_2) { Fabricate(:combined_outbox_item, event_key: event_key) }

    it { expect(result).to be_success }
  end

  context "when next is discarded" do
    let!(:outbox_item_2) { Fabricate(:combined_outbox_item, status: :discarded, event_key: event_key) }

    it { expect(result).to be_success }
  end
end
