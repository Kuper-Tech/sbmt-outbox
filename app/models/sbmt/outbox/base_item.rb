# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseItem < ApplicationRecord
      self.abstract_class = true

      class << self
        delegate :owner, to: :config

        def box_type
          raise NotImplementedError
        end

        def box_name
          @box_name ||= name.underscore
        end

        def config
          @config ||= lookup_config.new(box_name)
        end

        def partition_buckets
          @partition_buckets ||=
            (0...config.partition_size)
              .to_a
              .each_with_object({}) do |x, m|
                m[x] = (0...config.bucket_size)
                  .to_a
                  .select { |p| p % config.partition_size == x }
              end
        end

        def bucket_partitions
          @bucket_partitions ||=
            partition_buckets.each_with_object({}) do |(partition, buckets), m|
              buckets.each do |bucket|
                m[bucket] = partition
              end
            end
        end
      end

      enum status: {
        pending: 0,
        failed: 1,
        delivered: 2,
        discarded: 3
      }

      scope :for_processing, -> { where(status: :pending) }

      validates :uuid, :event_key, :bucket, :proto_payload, presence: true

      delegate :box_name, :config, to: "self.class"

      after_initialize do
        self.uuid ||= SecureRandom.uuid if has_attribute?(:uuid)
      end

      def for_processing?
        pending?
      end

      def options
        options = (self[:options] || {}).symbolize_keys
        options = default_options.deep_merge(extra_options).deep_merge(options)
        options.symbolize_keys
      end

      def transports
        if config.transports.empty?
          raise Error, "Transports are not defined"
        end

        if has_attribute?(:event_name)
          config.transports.fetch(event_name)
        else
          config.transports.fetch(:_all_)
        end
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

      def add_error(ex_or_msg)
        increment_errors_counter

        return unless has_attribute?(:error_log)

        self.error_log = "-----\n#{Time.zone.now} \n #{ex_or_msg}\n #{add_backtrace(ex_or_msg)}"
      end

      def partition
        self.class.bucket_partitions.fetch(bucket)
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

      def add_backtrace(ex)
        return unless ex.respond_to?(:backtrace)
        return if ex.backtrace.nil?

        ex.backtrace.join("\n")
      end
    end
  end
end
