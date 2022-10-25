# frozen_string_literal: true

module Sbmt
  module Outbox
    class OutboxItemConfig < BaseItemConfig
      private

      def lookup_config
        Outbox.yaml_config.dig(:outbox_items, box_name) || Outbox.yaml_config.dig(:items, box_name)
      end
    end
  end
end
