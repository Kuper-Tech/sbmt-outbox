# frozen_string_literal: true

module Sbmt
  module Outbox
    class Item < ApplicationRecord
      self.abstract_class = true

      IDEMPOTENCY_HEADER_NAME = "Idempotency-Key"
      SEQUENCE_HEADER_NAME = "Sequence-ID"
      EVENT_TIME_HEADER_NAME = "Created-At"

      enum status: {
        pending: 0,
        failed: 1,
        ignored: 2 # TODO: implement errors counter for failed items
      }

      validates :uuid, presence: true

      after_initialize do
        self.uuid ||= SecureRandom.uuid if has_attribute?(:uuid)
      end

      scope :for_precessing, -> { where(status: statuses.values_at(:pending)) }

      class << self
        def partition_size
          (Outbox.yaml_config.dig(:items, name, :partition_size) || 1).to_i
        end
      end

      def options
        options = (self[:options] || {})
        options = options.deep_merge(default_options).deep_merge(extra_options)
        options.symbolize_keys
      end

      def transports
        raise NotImplementedError
      end

      def payload_builder
        nil
      end

      private

      def default_options
        {
          headers: {
            IDEMPOTENCY_HEADER_NAME => uuid,
            SEQUENCE_HEADER_NAME => id.to_s,
            EVENT_TIME_HEADER_NAME => created_at&.to_datetime&.rfc3339(6)
          }
        }
      end

      # Override in descendants
      def extra_options
        {}
      end
    end
  end
end
