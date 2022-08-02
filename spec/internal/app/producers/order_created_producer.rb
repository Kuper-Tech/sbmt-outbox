# frozen_string_literal: true

class OrderCreatedProducer < Sbmt::Outbox::BaseProducer
  option :topic, default: lambda {
    config.dig(:producer, :topics, :orders)
  }

  def publish(outbox_item, payload)
    publish_to_kafka(payload, outbox_item.options)
  end
end
