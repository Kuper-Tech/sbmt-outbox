# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItem < DryInteractor
      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_ITEM_TIMEOUT", 30).to_i

      param :item_class, reader: :private
      param :item_id, reader: :private
      option :timeout, reader: :private, default: -> { TIMEOUT }

      delegate :logger, to: :Rails

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
            track_failed(result, outbox_item)
          else
            outbox_item.delete
            track_successed(outbox_item)
            Success(true)
          end
        rescue Dry::Monads::Do::Halt => e
          e.result
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

        track_failed("not found")
      end

      def build_payload(outbox_item)
        builder = outbox_item.payload_builder

        if builder
          payload = outbox_item.payload_builder.call(outbox_item)
          return payload if payload.success?

          track_failed(payload, outbox_item)
        else
          Success(outbox_item.proto_payload)
        end
      end

      def fetch_transports(outbox_item)
        transports = outbox_item.transports
        return Success(transports) if transports.present?

        track_failed("missing transports", outbox_item)
      end

      def process_item(transport, outbox_item, payload)
        result = Try do
          Timeout.timeout(timeout) do
            transport.call(outbox_item, payload)
          end
        end

        if result.error?
          return Failure("transport #{transport} raised error: #{result.exception.message}")
        end

        case (value = result.value!)
        when Dry::Monads::Result
          value
        when true
          Success()
        else
          Failure("transport #{transport} returned false")
        end
      end

      def track_failed(error, outbox_item = nil)
        failure = error.respond_to?(:failure) ? error.failure : error
        error_message = "Outbox item failed with error: #{failure}." \
                        "Record: #{item_class.name}##{item_id}"
        error_message += " #{outbox_item.log_details.to_json}" if outbox_item

        log_error(error_message)

        if outbox_item
          fail_outbox_item(outbox_item, error_message)
        else
          outbox_error = ProcessItemError.new(error_message)
          Outbox.error_tracker.error(outbox_error)
        end

        after_commit do
          Yabeda.outbox.error_counter
            .increment(item_class.metric_labels)
        end

        Failure(error_message)
      end

      def track_successed(outbox_item)
        log_success(
          "Outbox item successfully processed and deleted. " \
          "Record: #{item_class.name}##{item_id} #{outbox_item.log_details.to_json}"
        )

        after_commit do
          Yabeda.outbox.sent_counter
            .increment(item_class.metric_labels)

          Yabeda.outbox.last_sent_event_id
            .set(item_class.metric_labels, item_id)
        end
      end

      def fail_outbox_item(outbox_item, error_message)
        unless outbox_item.retriable?
          return outbox_item.failed!
        end

        outbox_item.increment(:errors_count)

        if outbox_item.max_retries_exceeded?
          error = MaxRetriesExceededError.new(error_message)
          Outbox.error_tracker.error(error)

          outbox_item.failed!
        else
          outbox_item.save! # just save errors_count
        end
      end

      def log_success(message)
        log_with_tags do
          logger.info(message)
        end
      end

      def log_error(message)
        log_with_tags do
          logger.error(message)
        end
      end

      def log_with_tags
        logger.tagged(outbox_name: item_class.outbox_name) do
          yield
        end
      end
    end
  end
end
