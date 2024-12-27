# frozen_string_literal: true

require "redlock"

module Sbmt
  module Outbox
    class BaseDeleteStaleItemsJob < Outbox.active_job_base_class
      MIN_RETENTION_PERIOD = 1.day
      LOCK_TTL = 10_800_000
      BATCH_SIZE = 1_000
      SLEEP_TIME = 0.5

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
            duration = item_class.config.retention

            validate_retention!(duration)

            logger.with_tags(box_type: box_type, box_name: box_name) do
              delete_stale_items(Time.current - duration)
            end
          else
            logger.log_info("Failed to acquire lock #{self.class.name}:#{item_class_name}")
          end
        end
      rescue Cutoff::CutoffExceededError
        logger.log_info("Lock timeout while processing #{item_class_name}")
      end

      private

      def validate_retention!(duration)
        return if duration >= MIN_RETENTION_PERIOD

        raise "Retention period for #{box_name} must be longer than #{MIN_RETENTION_PERIOD.inspect}"
      end

      def delete_stale_items(waterline)
        logger.log_info("Start deleting #{box_type} items for #{box_name} older than #{waterline}")

        case database_type
        when :postgresql
          postgres_delete_in_batches(waterline)
        when :mysql
          mysql_delete_in_batches(waterline)
        else
          raise "Unsupported database type"
        end

        logger.log_info("Successfully deleted #{box_type} items for #{box_name} older than #{waterline}")
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
      #     WHERE "items"."created_at" < '2023-05-01 00:00:00'
      #     LIMIT 1000
      #   )
      def postgres_delete_in_batches(waterline)
        table = item_class.arel_table
        condition = table[:created_at].lt(waterline)
        subquery = table
          .project(table[:id])
          .where(condition)
          .take(BATCH_SIZE)

        delete_statement = Arel::Nodes::DeleteStatement.new
        delete_statement.relation = table
        delete_statement.wheres = [table[:id].in(subquery)]

        loop do
          deleted_count = item_class
            .connection
            .execute(delete_statement.to_sql)
            .cmd_tuples

          logger.log_info("Deleted #{deleted_count} #{box_type} items for #{box_name} items")
          break if deleted_count == 0
          lock_timer.checkpoint!
          sleep(SLEEP_TIME)
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
      #   DELETE FROM `items`
      #   WHERE `items`.`created_at` < '2023-05-01 00:00:00'
      #   LIMIT 1000
      def mysql_delete_in_batches(waterline)
        loop do
          deleted_count = item_class
            .where(created_at: ...waterline)
            .limit(BATCH_SIZE)
            .delete_all

          logger.log_info("Deleted #{deleted_count} #{box_type} items for #{box_name} items")
          break if deleted_count == 0
          lock_timer.checkpoint!
          sleep(SLEEP_TIME)
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
    end
  end
end
