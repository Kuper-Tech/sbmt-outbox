# frozen_string_literal: true

class OutboxItem < Sbmt::Outbox::Item
  validates :event_name, :proto_payload, presence: true

  def transports
    [
      OrderCreatedProducer
    ]
  end
end
