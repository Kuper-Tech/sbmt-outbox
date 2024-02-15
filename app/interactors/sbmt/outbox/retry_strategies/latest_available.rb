# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class LatestAvailable < Base
        def call
          unless item.has_attribute?(:event_key)
            return Failure(:missing_event_key)
          end

          if item.event_key.nil?
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
          scope = item.class
            .where("id > ?", item)
            .where(event_key: item.event_key, status: Sbmt::Outbox::BaseItem.statuses[:delivered])

          if item.has_attribute?(:event_name) && item.event_name.present?
            scope = scope.where(event_name: item.event_name)
          end

          scope.exists?
        end
      end
    end
  end
end
