# frozen_string_literal: true

module Sbmt
  module Outbox
    class BaseCreateItem < Outbox::DryInteractor
      param :item_class, reader: :private
      option :attributes, reader: :private

      delegate :box_type, :box_name, to: :item_class

      def call
        record = item_class.new(attributes)

        if record.save
          track_last_stored_id(record.id)

          Success(record)
        else
          Failure(record.errors)
        end
      end

      private

      def track_last_stored_id(item_id)
        after_commit do
          Yabeda
            .send(box_type)
            .last_stored_event_id
            .set({name: box_name}, item_id)
        end
      end
    end
  end
end
