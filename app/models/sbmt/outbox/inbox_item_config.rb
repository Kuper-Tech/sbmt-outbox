# frozen_string_literal: true

module Sbmt
  module Outbox
    class InboxItemConfig < BaseItemConfig
      private

      def lookup_config
        Outbox.yaml_config.dig(:inbox_items, box_name)
      end
    end
  end
end
