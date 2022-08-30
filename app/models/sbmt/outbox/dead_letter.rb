# frozen_string_literal: true

module Sbmt
  module Outbox
    class DeadLetter < Outbox::ApplicationRecord
      self.abstract_class = true

      validates :proto_payload,
        :topic_name,
        presence: true

      def handler
        raise NotImplementedError
      end

      def payload
        raise NotImplementedError
      end

      def outbox_name
        @outbox_name ||= (metadata || {})["headers"][Item::OUTBOX_HEADER_NAME]
      end

      def metric_labels
        {
          name: outbox_name,
          topic: topic_name
        }
      end

      def log_details
        default_log_details.deep_merge(extra_log_details)
      end

      private

      def default_log_details
        {
          topic_name: topic_name,
          metadata: metadata,
          created_at: created_at.to_datetime.rfc3339(6)
        }
      end

      # Override in descendants
      def extra_log_details
        {}
      end
    end
  end
end
