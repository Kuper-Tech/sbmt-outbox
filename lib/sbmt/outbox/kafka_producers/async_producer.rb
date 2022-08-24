# frozen_string_literal: true

module Sbmt
  module Outbox
    module KafkaProducers
      class AsyncProducer < WaterDrop::AsyncProducer
        class << self
          def call(message, options)
            attempts_count ||= 0
            attempts_count += 1

            validate!(options)
            return unless WaterDrop.config.deliver

            if WaterDrop.config.raise_on_buffer_overflow
              deliver_async!(message, **options)
            else
              deliver_async(message, **options)
            end
          rescue Kafka::Error => e
            graceful_attempt?(attempts_count, message, options, e) ? retry : raise(e)
          end

          private

          def deliver_async(message, topic:, **options)
            deliver!(value, topic: topic, **options)
          rescue Kafka::BufferOverflow
            Outbox.logger.error "Message for `#{topic}` dropped due to buffer overflow"
          end

          def deliver_async!(message, topic:, **options)
            Sbmt::Outbox::KafkaProducers::DeliveryBoy
              .instance
              .deliver_async!(message, topic: topic, **options)
          end
        end
      end
    end
  end
end
