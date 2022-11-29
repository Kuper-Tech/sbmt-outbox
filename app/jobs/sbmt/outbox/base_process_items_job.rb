# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseProcessItemsJob
      include Sidekiq::Worker

      sidekiq_options lock: :until_executed,
        lock_ttl: Outbox.config.process_items.queue_timeout + Outbox.config.process_items.general_timeout + 5,
        lock_args_method: :lock_args,
        on_conflict: :log,
        retry: false

      class << self
        def lock_args(args)
          return [] if args.empty?
          raise ArgumentError if args.size < 2

          [args[0].to_s, args[1].to_i]
        end

        def enqueue
          item_classes.each do |item_class|
            item_class.config.partition_size.times do |partition_key|
              perform_async(item_class, partition_key)
            end
          end
        end

        def item_classes
          raise NotImplementedError
        end
      end

      attr_accessor :item_class,
        :partition_key,
        :last_id,
        :requeue

      delegate :config, :logger, to: "Sbmt::Outbox"
      delegate :box_type, :box_name, to: :item_class

      def perform(item_class_name, partition_key = 0, start_id = 0, enqueued_at = Time.current.to_s)
        self.item_class = item_class_name.is_a?(BaseItem) ? item_class_name : item_class_name.constantize
        self.partition_key = partition_key

        general_timer = Cutoff.new(config.process_items.general_timeout)
        requeue_timer = Cutoff.new(config.process_items.cutoff_timeout)

        logger.with_tags(box_type: box_type, box_name: box_name, box_partition: partition_key) do
          if job_expired?(enqueued_at)
            logger.log_failure(
              "Job has been expired before start processing #{box_type} items.\n" \
              "with: start_id: #{start_id}, enqueued_at: #{enqueued_at}"
            )

            return
          end

          process_items(start_id) do |processed_item_id|
            self.last_id = processed_item_id
            general_timer.checkpoint!
            requeue_timer.checkpoint!
          end
        end
      rescue Cutoff::CutoffExceededError
        if general_timer.exceeded?
          log_msg = "General timeout error when processing #{box_type} items"
        elsif requeue_timer.exceeded?
          log_msg = "Cutoff timeout error when processing #{box_type} items.\n" \
            "Requeuing job with: start_id: #{start_id}, last_id: #{last_id}"

          requeue!
        else
          raise
        end

        logger.log_failure(
          log_msg,
          box_type: box_type,
          box_name: box_name,
          box_partition: partition_key
        )
      end

      def job_expired?(enqueued_at)
        return false if enqueued_at.nil?

        enqueued_time = Time.zone.parse(enqueued_at)
        enqueued_time + config.process_items.queue_timeout < Time.current
      end

      def process_items(start_id)
        Outbox.database_switcher.use_slave do
          scope = item_class.for_processing.select(:id)
          scope = scope.where(partition_key: partition_key) if item_class.config.partition_size > 1

          scope.find_each(start: start_id, batch_size: config.process_items.batch_size) do |item|
            # TODO: check result object and use circuit breaker
            #       take into account :skip_processing failure
            Outbox.database_switcher.use_master do
              Sbmt::Outbox::ProcessItem.call(item_class, item.id)
            end
            yield item.id
          end
        end
      end

      def requeue!
        self.requeue = true
      end

      def requeue?
        !!requeue && !last_id.nil?
      end

      # Don't make it private method — it won't be called in that case!
      def after_unlock
        return unless requeue?

        Yabeda.send(box_type)
          .requeue_counter
          .increment(
            name: box_name,
            partition_key: partition_key
          )

        job_args = [item_class.name, partition_key, last_id + 1, Time.current.to_s]
        job_id = self.class.perform_async(*job_args)

        logger.log_info(
          "Requeued job #{self.class.name} with jid: #{job_id}, args: #{job_args}",
          box_type: box_type,
          box_name: box_name,
          box_partition: partition_key
        )
      end
    end
  end
end
