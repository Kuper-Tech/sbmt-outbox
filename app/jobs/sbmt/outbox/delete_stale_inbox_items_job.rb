# frozen_string_literal: true

module Sbmt
  module Outbox
    class DeleteStaleInboxItemsJob < BaseDeleteStaleItemsJob
      queue_as :inbox

      class << self
        def item_classes
          Outbox.inbox_item_classes
        end
      end
    end
  end
end
