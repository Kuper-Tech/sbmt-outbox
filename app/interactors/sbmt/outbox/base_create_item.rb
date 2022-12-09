# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseCreateItem < Outbox::DryInteractor
      param :item_class, reader: :private
      option :attributes, reader: :private

      delegate :box_type, :box_name, to: :item_class

      def call
        record = item_class.new(attributes)

        return Failure(:missing_event_key) unless attributes.key?(:event_key)
        event_key = attributes.fetch(:event_key)

        res = item_class.config.partition_strategy
          .new(event_key, item_class.config.bucket_size)
          .call
        record.bucket = res.value! if res.success?

        if record.save
          track_last_stored_id(record.id, record.partition)

          Success(record)
        else
          Failure(record.errors)
        end
      end

      private

      def track_last_stored_id(item_id, partition)
        after_commit do
          Yabeda
            .outbox
            .last_stored_event_id
            .set({type: box_type, name: box_name, partition: partition}, item_id)
        end
      end
    end
  end
end
