# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItem < DryInteractor
      class ProcessItemError < StandardError
      end

      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_ITEM_TIMEOUT", 30).to_i

      param :item_class, reader: :private
      param :item_id, reader: :private
      option :timeout, reader: :private, default: -> { TIMEOUT }

      def call
        item_class.transaction do
          outbox_item = yield fetch_outbox_item
          payload = yield build_payload(outbox_item)
          transports = yield fetch_transports(outbox_item)

          result = List(transports)
            .fmap { |transport| process_item(transport, outbox_item, payload) }
            .typed(Dry::Monads::Result)
            .traverse

          if result.failure?
            msg = "Export failed for #{item_class.name}##{outbox_item.id} with error: #{result.failure}"
            raise ProcessItemError, msg
          end

          outbox_item.delete

          Success(true)
        rescue Dry::Monads::Do::Halt => e
          e.result
        rescue ProcessItemError => e
          track_failed(e, defined?(outbox_item) ? outbox_item : nil)
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def fetch_outbox_item
        outbox_item = item_class
          .for_precessing
          .lock("FOR UPDATE")
          .find_by(id: item_id)
        return Success(outbox_item) if outbox_item

        Failure("#{item_class}#{item_id} not found")
      end

      def build_payload(outbox_item)
        builder = outbox_item.payload_builder

        if builder
          payload = outbox_item.payload_builder.call(outbox_item)
          return payload if payload.success?

          track_failed(payload.failure, outbox_item)
        else
          Success(outbox_item.proto_payload)
        end
      end

      def fetch_transports(outbox_item)
        transports = outbox_item.transports
        return Success(transports) if transports.present?

        track_failed("missing transports for #{item_class.name}##{outbox_item.id}", outbox_item)
      end

      def process_item(transport, outbox_item, payload)
        result = Timeout.timeout(timeout, ProcessItemError) do
          transport.call(outbox_item, payload)
        end

        case result
        when Dry::Monads::Result
          result
        when true
          Success()
        else
          Failure("Transport #{transport} returned false")
        end
      end

      def track_failed(error, outbox_item = nil)
        Outbox.error_tracker.error(error)
        outbox_item&.update_column(:status, Item.statuses[:failed])
        Failure(error.respond_to?(:message) ? error.message : error)
      end
    end
  end
end
