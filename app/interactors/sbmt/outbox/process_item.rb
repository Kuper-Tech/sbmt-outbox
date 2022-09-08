# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItem < Sbmt::Outbox::DryInteractor
      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_ITEM_TIMEOUT", 30).to_i

      param :item_class, reader: :private
      param :item_id, reader: :private
      option :timeout, reader: :private, default: -> { TIMEOUT }

      delegate :log_success, to: "Sbmt::Outbox.logger"

      def call
        outbox_item = nil

        item_class.transaction do
          Timeout.timeout(timeout) do
            outbox_item = yield fetch_outbox_item
            yield check_retry_strategy(outbox_item)
            payload = yield build_payload(outbox_item)
            transports = yield fetch_transports(outbox_item)

            transports.each do |transport|
              yield process_item(transport, outbox_item, payload)
            end

            outbox_item.delete
            track_successed(outbox_item)
            Success(outbox_item)
          end
        rescue Dry::Monads::Do::Halt => e
          e.result
        rescue Timeout::Error
          track_failed("execution expired", outbox_item)
          Failure(:timeout)
        rescue => e
          track_failed(e, outbox_item)
          Failure(e.message)
        end
      ensure
        report_metrics
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
        Failure(:not_found)
      end

      def check_retry_strategy(outbox_item)
        retry_strategy = outbox_item.retry_strategy

        result =
          if retry_strategy
            outbox_item.retry_strategy.call(outbox_item)
          else
            outbox_item.default_retry_strategy
          end

        result ? Success() : Failure(:skip_processing)
      end

      def build_payload(outbox_item)
        builder = outbox_item.payload_builder

        if builder
          payload = outbox_item.payload_builder.call(outbox_item)
          return payload if payload.success?

          track_failed("payload builder returned failure: #{payload.failure}", outbox_item)
          Failure(:payload_failure)
        else
          Success(outbox_item.proto_payload)
        end
      end

      def fetch_transports(outbox_item)
        transports = outbox_item.transports
        return Success(transports) if transports.present?

        track_failed("missing transports", outbox_item)
        Failure(:missing_transports)
      end

      def process_item(transport, outbox_item, payload)
        result = transport.call(outbox_item, payload)

        case result
        when Dry::Monads::Result
          if result.failure?
            track_failed("transport #{transport} returned failure: #{result.failure}")
            Failure(:transport_failure)
          else
            Success()
          end
        when true
          Success()
        else
          track_failed("transport #{transport} returned #{result.inspect}", outbox_item)
          Failure(:transport_failure)
        end
      end

      def track_failed(ex_or_msg, outbox_item = nil)
        log_failure(ex_or_msg, outbox_item)

        outbox_item&.increment_errors_counter!
        outbox_item&.processed!

        if outbox_item.nil? || outbox_item&.max_retries_exceeded?
          Outbox.error_tracker.error(
            ex_or_msg,
            outbox_name: item_class.outbox_name,
            item_class: item_class.name,
            item_id: item_id,
            item_details: outbox_item&.log_details&.to_json
          )
          counters[:error_counter] += 1
          outbox_item&.failed!
        else
          counters[:retry_counter] += 1
        end
      end

      def track_successed(outbox_item)
        msg = "Outbox item successfully processed and deleted.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{outbox_item.log_details.to_json}"
        log_success(msg, outbox_name: item_class.outbox_name)

        counters[:sent_counter] += 1
      end

      def log_failure(ex_or_msg, outbox_item = nil)
        msg = "Outbox item failed with error: #{ex_or_msg}.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{outbox_item&.log_details&.to_json}"

        backtrace = ex_or_msg.backtrace.join("\n") if ex_or_msg.respond_to?(:backtrace)

        Sbmt::Outbox.logger.log_failure(
          msg,
          outbox_name: item_class.outbox_name,
          backtrace: backtrace
        )
      end

      def report_metrics
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
