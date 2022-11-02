# frozen_string_literal: true

module Sbmt
  module Outbox
    # TODO: Safely rename class to ProcessOutboxItemsJob
    class ProcessItemsJob < Sbmt::Outbox::BaseProcessItemsJob
      sidekiq_options queue: :outbox

      class << self
        def item_classes
          @item_classes ||= Outbox.outbox_item_classes - Outbox.schked_ignore_outbox_item_classes
        end
      end
    end
  end
end
