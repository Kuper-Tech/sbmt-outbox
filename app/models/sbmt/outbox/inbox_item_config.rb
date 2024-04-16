# frozen_string_literal: true

module Sbmt
  module Outbox
    class InboxItemConfig < BaseItemConfig
      def polling_enabled?
        polling_enabled_for?(Sbmt::Outbox::Api::InboxItem)
      end

      private

      def lookup_config
        yaml_config.dig(:inbox_items, box_name)
      end
    end
  end
end
