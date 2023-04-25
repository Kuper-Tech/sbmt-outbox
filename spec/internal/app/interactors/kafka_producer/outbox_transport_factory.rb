# frozen_string_literal: true

module KafkaProducer
  class OutboxTransportFactory
    def self.build(topic:, kafka: {})
      ::Producer.new("outbox_item_topic", kafka)
    end
  end
end
