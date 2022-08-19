# frozen_string_literal: true

describe Sbmt::Outbox::KafkaProducers::SyncProducer do
  let(:delivery_instance) { instance_double(DeliveryBoy::Instance) }
  let(:message) { "kafka-message" }
  let(:topic) { "kafka-topic" }

  before do
    allow(Sbmt::Outbox::KafkaProducers::DeliveryBoy).to receive(:instance).and_return(delivery_instance)
  end

  it "delivers message to kafka" do
    expect(delivery_instance).to receive(:deliver).with(message, topic: topic)

    described_class.call(message, topic: topic)
  end
end
