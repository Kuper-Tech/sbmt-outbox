# frozen_string_literal: true

module Sbmt
  module Outbox
    class DeleteStaleItemsJob
      MIN_RETENTION_PERIOD = 1.day

      include Sidekiq::Worker

      sidekiq_options queue: :outbox,
        lock: :until_executed,
        lock_ttl: 3.hours.to_i,
        on_conflict: :log,
        retry: false

      class << self
        def enqueue
          Outbox.item_classes.each do |item_class|
            perform_async(item_class.to_s)
          end
        end
      end

      delegate :config, :logger, to: "Sbmt::Outbox"

      def perform(item_class_name)
        item_class = item_class_name.constantize

        duration = item_class.config.retention

        if duration < MIN_RETENTION_PERIOD
          raise "Retention period for #{item_class.outbox_name} must be longer than #{MIN_RETENTION_PERIOD.inspect}"
        end

        waterline = Time.current - duration

        logger.log_info(
          "Start deleting outbox items for #{item_class.outbox_name} older than #{waterline}",
          outbox_name: item_class.outbox_name
        )

        item_class
          .where("created_at < ?", waterline)
          .delete_all
      end
    end
  end
end
