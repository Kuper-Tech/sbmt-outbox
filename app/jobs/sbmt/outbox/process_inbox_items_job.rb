# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessInboxItemsJob < Sbmt::Outbox::BaseProcessItemsJob
      sidekiq_options queue: :inbox

      class << self
        def item_classes
          Outbox.inbox_item_classes
        end
      end
    end
  end
end
