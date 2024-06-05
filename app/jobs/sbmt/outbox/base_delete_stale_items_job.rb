# frozen_string_literal: true

require "redlock"

module Sbmt
  module Outbox
    class BaseDeleteStaleItemsJob < Outbox.active_job_base_class
      MIN_RETENTION_PERIOD = 1.day
      LOCK_TTL = 10_800_000
      BATCH_SIZE = 1000
      SLEEP_TIME = 1

      class << self
        def enqueue
          item_classes.each do |item_class|
            perform_later(item_class.to_s)
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

        client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
          Sbmt::Outbox.redis
        else
          Redis.new(config.redis)
        end

        lock_manager = Redlock::Client.new([client], retry_count: 0)

        lock_manager.lock("#{self.class.name}:#{item_class_name}:lock", LOCK_TTL) do |locked|
          if locked
            duration = item_class.config.retention

            validate_retention!(duration)

            logger.with_tags(box_type: box_type, box_name: box_name) do
              delete_stale_items(Time.current - duration)
            end
          else
            logger.log_info("Failed to acquire lock #{self.class.name}:#{item_class_name}")
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

        loop do
          ids = Outbox.database_switcher.use_slave do
            item_class.where("created_at < ?", waterline).limit(BATCH_SIZE).ids
          end
          break if ids.empty?

          item_class.where(id: ids).delete_all
          sleep SLEEP_TIME
        end

        logger.log_info("Successfully deleted #{box_type} items for #{box_name} older than #{waterline}")
      end
    end
  end
end
