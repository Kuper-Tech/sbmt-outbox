# frozen_string_literal: true

class OutboxItem < Sbmt::Outbox::Item
  def transports
    [
      OrderCreatedProducer
    ]
  end
end
