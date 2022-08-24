# frozen_string_literal: true

module Sbmt
  module Outbox
    module KafkaProducers
      class SyncProducer < WaterDrop::SyncProducer
        class << self
          def call(message, options)
            attempts_count ||= 0
            attempts_count += 1

            validate!(options)
            return unless WaterDrop.config.deliver

            deliver(message, **options)
          rescue Kafka::Error => e
            graceful_attempt?(attempts_count, message, options, e) ? retry : raise(e)
          end

          private

          def deliver(message, topic:, **options)
            Sbmt::Outbox::KafkaProducers::DeliveryBoy
              .instance
              .deliver(message, topic: topic, **options)
          end
        end
      end
    end
  end
end
