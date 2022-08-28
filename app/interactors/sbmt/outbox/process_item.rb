# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItem < Sbmt::Outbox::DryInteractor
      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_ITEM_TIMEOUT", 30).to_i

      param :item_class, reader: :private
      param :item_id, reader: :private
      option :timeout, reader: :private, default: -> { TIMEOUT }

      delegate :log_success, :log_failure, to: "Sbmt::Outbox.logger"

      def call
        outbox_item = nil

        item_class.transaction do
          Timeout.timeout(timeout) do
            outbox_item = yield fetch_outbox_item
            yield check_retry_strategy(outbox_item)
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
          end
        rescue Dry::Monads::Do::Halt => e
          e.result
        rescue Timeout::Error
          if outbox_item
            track_failed("execution expired", outbox_item)
          else
            track_fatal("execution expired")
          end
        end
      ensure
        track_metrics
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def fetch_outbox_item
        outbox_item = item_class
          .for_precessing
          .lock("FOR UPDATE")
          .find_by(id: item_id)
        return Success(outbox_item) if outbox_item

        track_fatal("not found")
      end

      def check_retry_strategy(outbox_item)
        retry_strategy = outbox_item.retry_strategy

        result =
          if retry_strategy
            outbox_item.retry_strategy.call(outbox_item)
          else
            outbox_item.default_retry_strategy
          end

        result ? Success() : Failure("Skip processing")
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
          transport.call(outbox_item, payload)
        end

        if result.error?
          Outbox.error_tracker.error(result.exception)
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

      def track_failed(error, outbox_item)
        error_message = "#{format_error_message(error)} #{outbox_item.log_details.to_json}"
        log_failure(error_message, outbox_name: item_class.outbox_name)

        outbox_item.increment_errors_counter!
        outbox_item.processed!

        if outbox_item.max_retries_exceeded?
          track_error_exception(error_message)
          counters[:error_counter] += 1
          outbox_item.failed!
        else
          counters[:retry_counter] += 1
        end

        Failure(error_message)
      end

      def track_fatal(error)
        error_message = format_error_message(error)
        log_failure(error_message, outbox_name: item_class.outbox_name)
        track_error_exception(error_message)

        counters[:error_counter] += 1

        Failure(error_message)
      end

      def track_successed(outbox_item)
        msg = "Outbox item successfully processed and deleted. " \
              "Record: #{item_class.name}##{item_id} #{outbox_item.log_details.to_json}"
        log_success(msg, outbox_name: item_class.outbox_name)

        counters[:sent_counter] += 1
      end

      def track_error_exception(error_message)
        error = ProcessItemError.new(error_message)
        Outbox.error_tracker.error(error)
      end

      def format_error_message(error)
        failure = error.respond_to?(:failure) ? error.failure : error
        "Outbox item failed with error: #{failure}. " \
        "Record: #{item_class.name}##{item_id}"
      end

      def track_metrics
        labels = item_class.metric_labels

        %i[error_counter retry_counter sent_counter].each do |counter_name|
          Yabeda.outbox
            .send(counter_name)
            .increment(labels, by: counters[counter_name])
        end

        return unless counters[:sent_counter] > 0

        Yabeda.outbox.last_sent_event_id
          .set(labels, item_id)
      end

      def counters
        @counters ||= Hash.new(0)
      end
    end
  end
end
