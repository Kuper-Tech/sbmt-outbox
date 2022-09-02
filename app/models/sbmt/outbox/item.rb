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
        failed: 1
      }

      validates :uuid, presence: true

      after_initialize do
        self.uuid ||= SecureRandom.uuid if has_attribute?(:uuid)
      end

      scope :for_precessing, -> { where(status: statuses[:pending]) }

      class << self
        def partition_size
          (Outbox.yaml_config.dig(:items, outbox_name, :partition_size) || 1).to_i
        end

        def max_retries
          (Outbox.yaml_config.dig(:items, outbox_name, :max_retries) || 0).to_i
        end

        def exponential_retry_interval
          (Outbox.yaml_config.dig(:items, outbox_name, :exponential_retry_interval) || false)
        end

        def minimal_retry_interval
          (Outbox.yaml_config.dig(:items, outbox_name, :minimal_retry_interval) || 10).to_i
        end

        def maximal_retry_interval
          (Outbox.yaml_config.dig(:items, outbox_name, :maximal_retry_interval) || 10 * 60).to_i
        end

        def multiplier_retry_interval
          (Outbox.yaml_config.dig(:items, outbox_name, :multiplier_retry_interval) || 2).to_i
        end

        def outbox_name
          @outbox_name ||= name.underscore
        end

        def metric_labels
          @metric_labels ||= {name: outbox_name}
        end
      end

      def options
        options = (self[:options] || {})
        options = options.deep_merge(default_options).deep_merge(extra_options)
        options.symbolize_keys
      end

      def retry_strategy
        nil
      end

      def default_retry_strategy
        return true unless exponential_retry_interval?
        return true if processed_at.nil?

        ExponentialRetryStrategy.new(
          minimal_interval: self.class.minimal_retry_interval,
          maximal_elapsed_time: self.class.maximal_retry_interval,
          multiplier: self.class.multiplier_retry_interval
        ).call(errors_count, processed_at)
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
        has_attribute?(:errors_count) && self.class.max_retries > 0
      end

      def exponential_retry_interval?
        retriable? && self.class.exponential_retry_interval && has_processed_at_attribute?
      end

      def has_processed_at_attribute?
        has_attribute?(:processed_at)
      end

      def max_retries_exceeded?
        return true unless retriable?

        errors_count > self.class.max_retries
      end

      def increment_errors_counter!
        return unless retriable?

        increment!(:errors_count)
      end

      def processed!
        return unless has_processed_at_attribute?

        update_column(:processed_at, Time.current)
      end

      private

      def default_options
        {
          headers: {
            OUTBOX_HEADER_NAME => self.class.outbox_name,
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
