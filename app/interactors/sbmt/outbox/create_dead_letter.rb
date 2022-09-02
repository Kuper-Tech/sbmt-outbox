# frozen_string_literal: true

module Sbmt
  module Outbox
    class CreateDeadLetter < Outbox::DryInteractor
      param :record_class, reader: :private

      option :proto_payload, reader: :private
      option :topic_name, reader: :private
      option :metadata, reader: :private
      option :error, reader: :private

      def call
        record = record_class.new(
          proto_payload: proto_payload,
          topic_name: topic_name,
          metadata: metadata,
          error: error.respond_to?(:message) ? error.message : error
        )

        if record.save
          Success(record)
        else
          Failure(record.errors)
        end
      ensure
        track_metrics(record) if record
      end

      private

      def track_metrics(record)
        Yabeda
          .dead_letters
          .error_counter
          .increment(record.metric_labels)
      end
    end
  end
end
