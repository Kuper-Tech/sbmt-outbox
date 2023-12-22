# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseCreateItem < Outbox::DryInteractor
      param :item_class, reader: :private
      option :attributes, reader: :private
      option :event_key, reader: :private, optional: true, default: -> { attributes[:event_key] }
      option :partition_by, reader: :private, optional: true, default: -> { attributes[:event_key] }

      delegate :box_type, :box_name, :owner, to: :item_class
      delegate :create_item_middlewares, to: "Sbmt::Outbox"

      def call
        middlewares = Middleware::Builder.new(create_item_middlewares)
        middlewares.call(item_class, attributes) do
          record = item_class.new(attributes)

          return Failure(:missing_event_key) unless event_key
          return Failure(:missing_partition_by) unless partition_by

          res = item_class.config.partition_strategy
            .new(partition_by, item_class.config.bucket_size)
            .call
          record.bucket = res.value! if res.success?

          if record.save
            track_last_stored_id(record.id, record.partition)
            track_counter(record.partition)

            Success(record)
          else
            Failure(record.errors)
          end
        end
      end

      private

      def track_last_stored_id(item_id, partition)
        Yabeda
          .outbox
          .last_stored_event_id
          .set({type: box_type, name: box_name, owner: owner, partition: partition}, item_id)
      end

      def track_counter(partition)
        Yabeda
          .outbox
          .created_counter
          .increment({type: box_type, name: box_name, owner: owner, partition: partition}, by: 1)
      end
    end
  end
end
