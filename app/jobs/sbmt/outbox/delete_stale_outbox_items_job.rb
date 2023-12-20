# frozen_string_literal: true

module Sbmt
  module Outbox
    class DeleteStaleOutboxItemsJob < BaseDeleteStaleItemsJob
      queue_as :outbox

      class << self
        def item_classes
          Outbox.outbox_item_classes
        end
      end
    end
  end
end
