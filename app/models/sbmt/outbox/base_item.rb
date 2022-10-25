# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseItem < ApplicationRecord
      self.abstract_class = true

      class << self
        def box_type
          raise NotImplementedError
        end

        def box_name
          @box_name ||= name.underscore
        end

        def config
          @config ||= lookup_config.new(box_name)
        end
      end

      enum status: {
        pending: 0,
        failed: 1,
        delivered: 2,
        discarded: 3
      }

      scope :for_processing, -> { where(status: :pending) }

      validates :uuid, presence: true

      delegate :box_name, :config, to: "self.class"

      after_initialize do
        self.uuid ||= SecureRandom.uuid if has_attribute?(:uuid)
      end

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

      def touch_processed_at
        self.processed_at = Time.current
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

      private

      def default_options
        raise NotImplementedError
      end

      # Override in descendants
      def extra_options
        {}
      end

      def default_log_details
        raise NotImplementedError
      end

      # Override in descendants
      def extra_log_details
        {}
      end
    end
  end
end
