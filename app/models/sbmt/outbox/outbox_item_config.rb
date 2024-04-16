# frozen_string_literal: true

module Sbmt
  module Outbox
    class OutboxItemConfig < BaseItemConfig
      def polling_enabled?
        polling_enabled_for?(Sbmt::Outbox::Api::OutboxItem)
      end

      private

      def lookup_config
        yaml_config.dig(:outbox_items, box_name)
      end
    end
  end
end
