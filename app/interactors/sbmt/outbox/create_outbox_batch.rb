# frozen_string_literal: true

require "sbmt/outbox/metrics/utils"

# Provides ability to insert records in batches.
# It allows to have different headers, event_key and partition_by between set of attributes,
# but for predictability of metrics results better to have same headers across items

module Sbmt
  module Outbox
    class CreateOutboxBatch < Outbox::DryInteractor
      param :item_class, reader: :private
      option :batch_attributes, reader: :private

      delegate :box_type, :box_name, :owner, to: :item_class
      delegate :create_batch_middlewares, to: "Sbmt::Outbox"

      def call
        middlewares = Middleware::Builder.new(create_batch_middlewares)
        middlewares.call(item_class, batch_attributes) do
          attributes_to_insert = batch_attributes.map do |attributes|
            event_key = attributes[:event_key]
            partition_by = attributes.delete(:partition_by) || event_key

            return Failure(:missing_partition_by) unless partition_by
            return Failure(:missing_event_key) unless event_key

            # to get default values for some attributes, including uuid
            record = item_class.new(attributes)

            res = item_class.config.partition_strategy
              .new(partition_by, item_class.config.bucket_size)
              .call
            record.bucket = res.value! if res.success?

            # those 2 lines needed for rails 6, as it does not set timestamps
            record.created_at ||= Time.zone.now
            record.updated_at ||= record.created_at

            record.attributes.reject { |_, value| value.nil? }
          end

          inserted_items = item_class.insert_all(attributes_to_insert, returning: [:id, :bucket])
          inserted_items.rows.each do |(record_id, bucket)|
            partition = item_class.bucket_partitions.fetch(bucket)
            track_last_stored_id(record_id, partition)
            track_counter(partition)
          end

          Success(inserted_items.rows.map(&:first))
        rescue => e
          Failure(e.message)
        end
      end

      private

      def track_last_stored_id(item_id, partition)
        Yabeda
          .outbox
          .last_stored_event_id
          .set({type: box_type, name: Sbmt::Outbox::Metrics::Utils.metric_safe(box_name), owner: owner, partition: partition}, item_id)
      end

      def track_counter(partition)
        Yabeda
          .outbox
          .created_counter
          .increment({type: box_type, name: Sbmt::Outbox::Metrics::Utils.metric_safe(box_name), owner: owner, partition: partition}, by: 1)
      end
    end
  end
end
