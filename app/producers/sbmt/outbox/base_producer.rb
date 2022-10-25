# frozen_string_literal: true

# Application responder from which all WaterDrop responders should inherit
module Sbmt
  module Outbox
    class BaseProducer
      extend Dry::Initializer

      class << self
        def [](name:, topic:)
          klass = Class.new(self) do
            define_method :topic do
              @topic ||= topic
            end
          end

          Sbmt::Outbox::BaseProducer.const_set("#{name.classify}Producer", klass)
        end

        def call(outbox_item, payload)
          new.publish(outbox_item, payload)
        end
      end

      option :producer, default: -> { KafkaProducers::SyncProducer }
      option :async_producer, default: -> { KafkaProducers::AsyncProducer }
      option :config, default: -> { Outbox.yaml_config }

      def publish(outbox_item, payload)
        publish_to_kafka(payload, outbox_item.options)
      end

      private

      def publish_to_kafka(message, params = {})
        producer.call(message, params.merge(topic: topic))
        true
      rescue Kafka::DeliveryFailed, OpenSSL::X509::StoreError => e
        log_error(e)

        false
      end

      def async_publish_to_kafka(message, params = {}, max_retries = 3)
        retries ||= 0

        async_producer.call(message, params.merge(topic: topic))
        true
      rescue Kafka::BufferOverflow => e
        if retries > max_retries
          log_error(e)
          return false
        end

        sleep_time = rand(1..3).to_f / 10
        sleep sleep_time unless Rails.env.test?
        retries += 1

        retry
      end

      def ignore_kafka_errors?
        config[:ignore_kafka_errors].present? && config[:ignore_kafka_errors].to_s == "true"
      end

      def log_error(error)
        return true if ignore_kafka_errors?

        Rails.logger.error "KAFKA ERROR: #{error.message}\n#{error.backtrace.join("\n")}"
        Outbox.error_tracker.error(error)
      end
    end
  end
end
