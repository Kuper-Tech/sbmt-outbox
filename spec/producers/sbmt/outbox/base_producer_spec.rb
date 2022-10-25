# frozen_string_literal: true

describe Sbmt::Outbox::BaseProducer do
  subject(:producer) { OutboxItem::PRODUCER.new }

  it "determines a valid topic" do
    expect(producer.topic).to eq "orders"
  end
end
