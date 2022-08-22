# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItemsJob
      include Sidekiq::Worker

      BATCH_SIZE = ENV.fetch("SBMT_OUTBOX__APP__PROCESSING_BATCH_SIZE", 100).to_i

      sidekiq_options queue: :outbox,
        lock: :until_executed,
        # Actually, we don't know how long the processing will be
        lock_ttl: 15.minutes.to_i,
        retry: false

      def self.enqueue
        Outbox.item_classes.each do |item_class|
          item_class.partition_size.times do |partition_key|
            perform_async(item_class, partition_key)
          end
        end
      end

      def perform(item_class_name = nil, partition_key = 1)
        return self.class.enqueue unless item_class_name

        item_class = item_class_name.constantize

        scope = item_class
          .for_precessing
          .select(:id)

        scope = scope.where(partition_key: partition_key) if item_class.partition_size > 1

        scope.find_each(batch_size: BATCH_SIZE) do |item|
          ProcessItem.call(item_class, item.id)
        end
      end
    end
  end
end
