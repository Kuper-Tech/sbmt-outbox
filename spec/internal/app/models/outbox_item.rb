# frozen_string_literal: true

class OutboxItem < Sbmt::Outbox::OutboxItem
  validates :event_name, :proto_payload, presence: true

  PRODUCER = Sbmt::Outbox::BaseProducer[
    name: "order_created",
    topic: Sbmt::Outbox.yaml_config.dig(:producer, :topics, :order_created)
  ]

  def transports
    [PRODUCER]
  end
end
