# frozen_string_literal: true

require "redlock"

module Sbmt
  module Outbox
    class BaseDeleteStaleItemsJob < Outbox.active_job_base_class
      LOCK_TTL = 10_800_000

      class << self
        def enqueue
          item_classes.each do |item_class|
            delay = rand(15).seconds
            set(wait: delay).perform_later(item_class.to_s)
          end
        end

        def item_classes
          raise NotImplementedError
        end
      end

      delegate :config, :logger, to: "Sbmt::Outbox"
      delegate :box_type, :box_name, to: :item_class

      attr_accessor :item_class, :lock_timer

      def perform(item_class_name)
        self.item_class = item_class_name.constantize

        client = if Gem::Version.new(Redlock::VERSION) >= Gem::Version.new("2.0.0")
          Sbmt::Outbox.redis
        else
          Redis.new(config.redis)
        end

        self.lock_timer = Cutoff.new(LOCK_TTL / 1000)
        lock_manager = Redlock::Client.new([client], retry_count: 0)

        lock_manager.lock("#{self.class.name}:#{item_class_name}:lock", LOCK_TTL) do |locked|
          if locked
            duration_failed = item_class.config.retention
            duration_delivered = item_class.config.retention_delivered_items

            validate_retention!(duration_delivered, duration_failed)

            logger.with_tags(box_type: box_type, box_name: box_name) do
              delete_stale_items(Time.current - duration_failed, Time.current - duration_delivered)
            end
          else
            logger.log_info("Failed to acquire lock #{self.class.name}:#{item_class_name}")
          end
        end
      rescue Cutoff::CutoffExceededError
        logger.log_info("Lock timeout while processing #{item_class_name}")
      end

      private

      def validate_retention!(duration_delivered, duration_failed)
        validate_retention_for!(
          duration: duration_delivered,
          min_period: item_class.config.delivered_min_retention_period,
          error_message: "Retention period for #{box_name} must be longer than #{item_class.config.delivered_min_retention_period.inspect}"
        )

        validate_retention_for!(
          duration: duration_failed,
          min_period: item_class.config.min_retention_period,
          error_message: "Retention period for #{box_name} must be longer than #{item_class.config.min_retention_period.inspect}"
        )
      end

      def validate_retention_for!(duration:, min_period:, error_message:)
        raise error_message if duration < min_period
      end

      def delete_stale_items(waterline_failed, waterline_delivered)
        logger.log_info("Start deleting #{box_type} items for #{box_name} older than: failed and discarded items #{waterline_failed} and delivered items #{waterline_delivered}")

        case database_type
        when :postgresql
          postgres_delete_in_batches(waterline_failed, waterline_delivered)
        when :mysql
          mysql_delete_in_batches(waterline_failed, waterline_delivered)
        else
          raise "Unsupported database type"
        end

        logger.log_info("Successfully deleted #{box_type} items for #{box_name} older than: failed and discarded items #{waterline_failed} and delivered items #{waterline_delivered}")
      end

      # Deletes stale items from PostgreSQL database in batches
      #
      # This method efficiently deletes items older than the given waterline
      # using a subquery approach to avoid locking large portions of the table.
      #
      #
      # Example SQL generated for deletion:
      #   DELETE FROM "items"
      #   WHERE "items"."id" IN (
      #     SELECT "items"."id"
      #     FROM "items"
      #     WHERE (
      #       "items"."status" IN (2) AND "items"."created_at" BETWEEN "2025-01-29 12:18:32.917836" AND "2025-01-29 12:18:32.927596" LIMIT 1000
      #     )
      #   )
      def postgres_delete_in_batches(waterline_failed, waterline_delivered)
        status_delivered = item_class.statuses[:delivered]
        status_failed_discarded = item_class.statuses.values_at(:failed, :discarded)

        delete_items_in_batches_with_between(waterline_delivered, status_delivered)
        delete_items_in_batches_with_between(waterline_failed, status_failed_discarded)
      end

      def delete_items_in_batches_with_between(waterline, statuses)
        table = item_class.arel_table
        batch_size = item_class.config.deletion_batch_size
        time_window = item_class.config.deletion_time_window
        min_date = item_class.where(table[:status].in(statuses)).minimum(:created_at)
        deleted_count = nil

        while min_date && min_date < waterline
          max_date = [min_date + time_window, waterline].min

          loop do
            subquery = table
              .project(table[:id])
              .where(table[:status].in(statuses))
              .where(table[:created_at].between(min_date..max_date))
              .take(batch_size)

            delete_statement = Arel::Nodes::DeleteStatement.new
            delete_statement.relation = table
            delete_statement.wheres = [table[:id].in(subquery)]

            track_deleted_latency do
              deleted_count = item_class.connection.execute(delete_statement.to_sql).cmd_tuples
            end

            track_deleted_counter(deleted_count)

            logger.log_info("Deleted #{deleted_count} #{box_type} items for #{box_name} between #{min_date} and #{max_date}")
            break if deleted_count < batch_size
            lock_timer.checkpoint!
            sleep(item_class.config.deletion_sleep_time) if deleted_count > 0
          end
          min_date = max_date
        end
      end

      # Deletes stale items from MySQL database in batches
      #
      # This method efficiently deletes items older than the given waterline
      # using MySQL's built-in LIMIT clause for DELETE statements.
      #
      # The main difference from the PostgreSQL method is that MySQL allows
      # direct use of LIMIT in DELETE statements, simplifying the query.
      # This approach doesn't require a subquery, making it more straightforward.
      #
      # Example SQL generated for deletion:
      #   DELETE FROM "items"
      #   WHERE (
      #     "items"."status" IN (2) AND "items"."created_at" BETWEEN "2024-12-29 18:34:25.369234" AND "2024-12-29 22:34:25.369234" LIMIT 1000
      #   )
      def mysql_delete_in_batches(waterline_failed, waterline_delivered)
        status_delivered = item_class.statuses[:delivered]
        status_failed_discarded = [item_class.statuses.values_at(:failed, :discarded)]

        delete_items_in_batches_with_between_mysql(waterline_delivered, status_delivered)
        delete_items_in_batches_with_between_mysql(waterline_failed, status_failed_discarded)
      end

      def delete_items_in_batches_with_between_mysql(waterline, statuses)
        batch_size = item_class.config.deletion_batch_size
        time_window = item_class.config.deletion_time_window
        min_date = item_class.where(status: statuses).minimum(:created_at)
        deleted_count = nil

        while min_date && min_date < waterline
          max_date = [min_date + time_window, waterline].min

          loop do
            track_deleted_latency do
              deleted_count = item_class
                .where(status: statuses, created_at: min_date..max_date)
                .limit(batch_size)
                .delete_all
            end

            track_deleted_counter(deleted_count)

            logger.log_info("Deleted #{deleted_count} #{box_type} items for #{box_name} between #{min_date} and #{max_date}")
            break if deleted_count < batch_size
            lock_timer.checkpoint!
            sleep(item_class.config.deletion_sleep_time) if deleted_count > 0
          end
          min_date = max_date
        end
      end

      def database_type
        adapter_name = item_class.connection.adapter_name.downcase
        case adapter_name
        when "postgresql", "postgis"
          :postgresql
        when "mysql2"
          :mysql
        else
          :unknown
        end
      end

      def track_deleted_counter(deleted_count)
        ::Yabeda
          .outbox
          .deleted_counter
          .increment({box_type: box_type, box_name: box_name}, by: deleted_count)
      end

      def track_deleted_latency
        ::Yabeda
          .outbox
          .delete_latency
          .measure({box_type: box_type, box_name: box_name}) do
          yield
        end
      end
    end
  end
end
