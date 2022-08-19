# frozen_string_literal: true

describe Sbmt::Outbox::KafkaProducers::DeliveryBoy do
  describe ".instance" do
    it "creates DeliveryBoy instance with outbox config" do
      expect(described_class.instance.send(:config)).not_to eq ::DeliveryBoy.config
    end
  end

  describe ".config" do
    it "overrides DeliveryBoy config required_acks" do
      expect(described_class.config.required_acks).to eq(-1)
    end
  end
end
