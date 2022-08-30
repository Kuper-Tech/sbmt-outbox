# frozen_string_literal: true

describe Sbmt::Outbox::DeadLetter do
  let(:record) { Fabricate.build(:dead_letter) }

  describe "implementation API" do
    let(:base_record) { described_class.new }

    it "#handler" do
      expect { base_record.handler }.to raise_error(NotImplementedError)
    end

    it "#payload" do
      expect { base_record.payload }.to raise_error(NotImplementedError)
    end
  end

  describe "#metric_labels" do
    it "reads outbox name from headers" do
      expect(record.metric_labels).to include(
        name: "test-outbox",
        topic: "test-topic"
      )
    end
  end
end
