# frozen_string_literal: true

module KafkaProducer
  class OutboxTransportFactory
    def self.build(topic:, kafka: {})
      ::Producer.new(topic: topic, kafka: kafka)
    end
  end
end
