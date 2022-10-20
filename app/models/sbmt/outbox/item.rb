# frozen_string_literal: true

module Sbmt
  module Outbox
    class Item < ApplicationRecord
      self.abstract_class = true

      IDEMPOTENCY_HEADER_NAME = "Idempotency-Key"
      SEQUENCE_HEADER_NAME = "Sequence-ID"
      EVENT_TIME_HEADER_NAME = "Created-At"
      OUTBOX_HEADER_NAME = "Outbox-Name"

      enum status: {
        pending: 0,
        failed: 1,
        delivered: 2,
        discarded: 3
      }

      validates :uuid, presence: true

      after_initialize do
        self.uuid ||= SecureRandom.uuid if has_attribute?(:uuid)
      end

      scope :for_processing, -> { where(status: statuses[:pending]) }

      class << self
        def outbox_name
          @outbox_name ||= name.underscore
        end

        def config
          @config ||= Sbmt::Outbox::ItemConfig.new(outbox_name)
        end
      end

      delegate :outbox_name, :config, to: "self.class"

      def options
        options = (self[:options] || {})
        options = options.deep_merge(default_options).deep_merge(extra_options)
        options.symbolize_keys
      end

      def transports
        raise NotImplementedError
      end

      def log_details
        default_log_details.deep_merge(extra_log_details)
      end

      def payload_builder
        nil
      end

      def retriable?
        config.max_retries > 0
      end

      def max_retries_exceeded?
        return true unless retriable?

        errors_count > config.max_retries
      end

      def increment_errors_counter
        increment(:errors_count)
      end

      def touch_processed_at
        self.processed_at = Time.current
      end

      private

      def default_options
        {
          headers: {
            OUTBOX_HEADER_NAME => outbox_name,
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

      def default_log_details
        {
          uuid: uuid,
          status: status,
          created_at: created_at.to_datetime.rfc3339(6)
        }.tap do |row|
          row[:errors_count] = errors_count if retriable?
        end
      end

      # Override in descendants
      def extra_log_details
        {}
      end
    end
  end
end
