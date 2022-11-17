# frozen_string_literal: true

module Sbmt
  module Outbox
    class OutboxItem < BaseItem
      self.abstract_class = true

      IDEMPOTENCY_HEADER_NAME = "Idempotency-Key"
      SEQUENCE_HEADER_NAME = "Sequence-ID"
      EVENT_TIME_HEADER_NAME = "Created-At"
      OUTBOX_HEADER_NAME = "Outbox-Name"
      DISPATCH_TIME_HEADER_NAME = "Dispatched-At"

      class << self
        alias_method :outbox_name, :box_name

        def box_type
          :outbox
        end

        def lookup_config
          Sbmt::Outbox::OutboxItemConfig
        end
      end

      delegate :outbox_name, :config, to: "self.class"

      private

      def default_options
        {
          headers: {
            OUTBOX_HEADER_NAME => outbox_name,
            IDEMPOTENCY_HEADER_NAME => uuid,
            SEQUENCE_HEADER_NAME => id.to_s,
            EVENT_TIME_HEADER_NAME => created_at&.to_datetime&.rfc3339(6),
            DISPATCH_TIME_HEADER_NAME => Time.current.to_datetime.rfc3339(6)
          }
        }
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
