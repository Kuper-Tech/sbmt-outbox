# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItemsJob
      include Sidekiq::Worker

      BATCH_SIZE = ENV.fetch("SBMT_OUTBOX__APP__PROCESSING_BATCH_SIZE", 100).to_i
      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_ITEM_TIMEOUT", 5).to_i

      sidekiq_options queue: :outbox,
        lock: :until_executed,
        lock_ttl: (BATCH_SIZE * TIMEOUT) + 1.minute.to_i,
        lock_args_method: :lock_args,
        retry: false

      class << self
        def lock_args(args)
          return [] if args.empty?
          raise ArgumentError if args.size < 2

          [args[0].to_s, args[1].to_i]
        end

        def enqueue
          Outbox.item_classes.each do |item_class|
            item_class.partition_size.times do |partition_key|
              perform_async(item_class, partition_key, 0)
            end
          end
        end
      end

      def perform(item_class_name = nil, partition_key = 0, start_id = 0)
        return self.class.enqueue unless item_class_name

        @requeue_args = [item_class_name, partition_key]

        item_class = item_class_name.constantize

        scope = item_class
          .for_precessing
          .select(:id)

        scope = scope.where(partition_key: partition_key) if item_class.partition_size > 1
        scope = scope.where("id >= ?", start_id) if start_id > 0

        scope.order(:id).limit(BATCH_SIZE + 1).each_with_index do |item, i|
          # we have more than BATCH_SIZE items, so reenqueue the job
          if i >= BATCH_SIZE
            @requeue = true
            @requeue_args << item.id
            break
          else
            ProcessItem.call(item_class, item.id, timeout: TIMEOUT)
          end
        end
      end

      def after_unlock
        self.class.perform_async(*@requeue_args) if requeue?
      end

      def requeue?
        !!@requeue
      end
    end
  end
end
