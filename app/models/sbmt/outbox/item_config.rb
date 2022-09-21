# frozen_string_literal: true

module Sbmt
  module Outbox
    class ItemConfig
      delegate :yaml_config, to: "Sbmt::Outbox"

      def initialize(outbox_name)
        self.outbox_name = outbox_name
      end

      def partition_size
        (options[:partition_size] || 1).to_i
      end

      def retention
        @retention ||= ActiveSupport::Duration.parse(options[:retention] || "P1W")
      end

      def max_retries
        (options[:max_retries] || 0).to_i
      end

      def minimal_retry_interval
        (options[:minimal_retry_interval] || 10).to_i
      end

      def maximal_retry_interval
        (options[:maximal_retry_interval] || 600).to_i
      end

      def multiplier_retry_interval
        (options[:multiplier_retry_interval] || 2).to_i
      end

      def retry_strategies
        @retry_strategies ||= Array.wrap(options[:retry_strategies]).map do |str_name|
          "Sbmt::Outbox::RetryStrategies::#{str_name.classify}".constantize
        end
      end

      private

      attr_accessor :outbox_name

      def options
        @options ||= Outbox.yaml_config.dig(:items, outbox_name) || {}
      end
    end
  end
end
