# frozen_string_literal: true

require "redlock"

module Sbmt
  module Outbox
    class BaseDeleteStaleItemsJob
      include Sidekiq::Worker

      MIN_RETENTION_PERIOD = 1.day

      class << self
        def enqueue
          item_classes.each do |item_class|
            perform_async(item_class.to_s)
          end
        end

        def item_classes
          raise NotImplementedError
        end
      end

      delegate :config, :logger, to: "Sbmt::Outbox"
      delegate :box_type, :box_name, to: :item_class

      attr_accessor :item_class

      def perform(item_class_name)
        self.item_class = item_class_name.constantize

        lock_manager = Redlock::Client.new(config.redis_servers, retry_count: 0)

        lock_manager.lock("lock:#{self.class.name}:#{args.join(":")}", 1) do |locked|
          if locked
            duration = item_class.config.retention

            validate_retention!(duration)

            logger.with_tags(box_type: box_type, box_name: box_name) do
              delete_stale_items(Time.current - duration)
            end
          else
            logger.log_info("Failed to acquire lock #{self.class.name}")
          end
        end
      end

      private

      def validate_retention!(duration)
        return if duration >= MIN_RETENTION_PERIOD

        raise "Retention period for #{box_name} must be longer than #{MIN_RETENTION_PERIOD.inspect}"
      end

      def delete_stale_items(waterline)
        logger.log_info("Start deleting #{box_type} items for #{box_name} older than #{waterline}")

        item_class
          .where("created_at < ?", waterline)
          .in_batches(of: 1000) do |scope|
            scope.delete_all
            sleep 1
          end

        logger.log_info("Successfully deleted #{box_type} items for #{box_name} older than #{waterline}")
      end
    end
  end
end
