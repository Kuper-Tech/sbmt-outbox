# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class CompactedLog < Outbox::DryInteractor
        param :outbox_item

        def call
          unless outbox_item.has_attribute?(:event_key)
            return Failure(:missing_event_key)
          end

          if outbox_item.event_key.nil?
            return Failure(:empty_event_key)
          end

          if delivered_later?
            Failure(:discard_item)
          else
            Success()
          end
        end

        private

        def delivered_later?
          scope = outbox_item.class
            .where("id > ?", outbox_item)
            .where(event_key: outbox_item.event_key, status: Sbmt::Outbox::BaseItem.statuses[:delivered])

          if outbox_item.has_attribute?(:event_name) && outbox_item.event_name.present?
            scope = scope.where(event_name: outbox_item.event_name)
          end

          scope.exists?
        end
      end
    end
  end
end
