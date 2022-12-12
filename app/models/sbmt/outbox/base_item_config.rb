# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseItemConfig
      DEFAULT_BUCKET_SIZE = 16
      DEFAULT_PARTITION_STRATEGY = :number

      def initialize(box_name)
        self.box_name = box_name

        validate!
      end

      def bucket_size
        @bucket_size ||= (options[:bucket_size] || Outbox.yaml_config.fetch(:bucket_size, DEFAULT_BUCKET_SIZE)).to_i
      end

      def partition_size
        @partition_size ||= (options[:partition_size] || 1).to_i
      end

      def retention
        @retention ||= ActiveSupport::Duration.parse(options[:retention] || "P1W")
      end

      def max_retries
        @max_retries ||= (options[:max_retries] || 0).to_i
      end

      def minimal_retry_interval
        @minimal_retry_interval ||= (options[:minimal_retry_interval] || 10).to_i
      end

      def maximal_retry_interval
        @maximal_retry_interval ||= (options[:maximal_retry_interval] || 600).to_i
      end

      def multiplier_retry_interval
        @multiplier_retry_interval ||= (options[:multiplier_retry_interval] || 2).to_i
      end

      def retry_strategies
        @retry_strategies ||= Array.wrap(options[:retry_strategies]).map do |str_name|
          "Sbmt::Outbox::RetryStrategies::#{str_name.classify}".constantize
        end
      end

      def partition_strategy
        return @partition_strategy if defined?(@partition_strategy)

        str_name = options.fetch(:partition_strategy, DEFAULT_PARTITION_STRATEGY)
        @partition_strategy = "Sbmt::Outbox::PartitionStrategies::#{str_name.classify}Partitioning".constantize
      end

      private

      attr_accessor :box_name

      def options
        @options ||= lookup_config || {}
      end

      def lookup_config
        raise NotImplementedError
      end

      def validate!
        raise ConfigError, "Bucket size should be greater or equal to partition size" if partition_size > bucket_size
      end
    end
  end
end
