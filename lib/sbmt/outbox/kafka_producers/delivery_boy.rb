# frozen_string_literal: true

module Sbmt
  module Outbox
    module KafkaProducers
      module DeliveryBoy
        module_function

        def instance
          @instance ||= ::DeliveryBoy::Instance.new(config, Outbox.logger)
        end

        def config
          @config ||= ::DeliveryBoy.config.clone.tap do |config|
            unless (ra = required_acks).nil?
              config.required_acks = ra
            end
          end
        end

        def required_acks
          value = Outbox.yaml_config.dig(:kafka, :required_acks)
          return if value.nil?

          Integer(value)
        end
      end
    end
  end
end

at_exit { Sbmt::Outbox::KafkaProducers::DeliveryBoy.instance.shutdown }
