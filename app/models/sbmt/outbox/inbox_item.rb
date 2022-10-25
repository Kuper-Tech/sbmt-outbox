# frozen_string_literal: true

module Sbmt
  module Outbox
    class InboxItem < BaseItem
      self.abstract_class = true

      class << self
        alias_method :inbox_name, :box_name

        def box_type
          :inbox
        end

        def lookup_config
          Sbmt::Outbox::InboxItemConfig
        end
      end

      delegate :inbox_name, :config, to: "self.class"

      private

      def default_options
        {}
      end

      def default_log_details
        {
          uuid: uuid,
          status: status,
          created_at: created_at.to_datetime.rfc3339(6),
          errors_count: errors_count
        }
      end
    end
  end
end
