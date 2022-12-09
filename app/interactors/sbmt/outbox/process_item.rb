# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessItem < Sbmt::Outbox::DryInteractor
      param :item_class, reader: :private
      param :item_id, reader: :private

      METRICS_COUNTERS = %i[error_counter retry_counter sent_counter fetch_error_counter discarded_counter].freeze

      delegate :log_success, :log_failure, to: "Sbmt::Outbox.logger"
      delegate :box_type, :box_name, to: :item_class

      attr_accessor :process_latency

      def call
        log_success(
          "Start processing #{box_type} item.\n" \
          "Record: #{item_class.name}##{item_id}"
        )

        item = nil

        item_class.transaction do
          item = yield fetch_item

          if item.processed_at?
            item.config.retry_strategies.each do |retry_strategy|
              yield check_retry_strategy(item, retry_strategy)
            end
          else
            self.process_latency = Time.current - item.created_at
          end

          payload = yield build_payload(item)
          transports = yield fetch_transports(item)

          transports.each do |transport|
            yield process_item(transport, item, payload)
          end

          track_successed(item)

          Success(item)
        rescue Dry::Monads::Do::Halt => e
          e.result
        rescue => e
          track_failed(e, item)
          Failure(e.message)
        end
      ensure
        report_metrics(item)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

      def fetch_item
        item = item_class
          .for_processing
          .lock("FOR UPDATE")
          .find_by(id: item_id)
        return Success(item) if item

        track_failed("not found")
        Failure(:not_found)
      end

      def check_retry_strategy(item, retry_strategy)
        result = retry_strategy.call(item)

        return Success() if result.success?

        case result.failure
        when :skip_processing
          Failure(:skip_processing)
        when :discard_item
          track_discarded(item)
          Failure(:discard_item)
        else
          track_failed("retry stratagy returned unknown failure: #{result.failure}")
          Failure(:retry_strategy_failure)
        end
      end

      def build_payload(item)
        builder = item.payload_builder

        if builder
          payload = item.payload_builder.call(item)
          return payload if payload.success?

          track_failed("payload builder returned failure: #{payload.failure}", item)
          Failure(:payload_failure)
        else
          Success(item.proto_payload)
        end
      end

      def fetch_transports(item)
        transports = item.transports
        return Success(transports) if transports.present?

        track_failed("missing transports", item)
        Failure(:missing_transports)
      end

      def process_item(transport, item, payload)
        transport_error = nil

        result = item_class.transaction(requires_new: true) do
          transport.call(item, payload)
        rescue => e
          transport_error = e
          raise ActiveRecord::Rollback
        end

        if transport_error
          track_failed(transport_error, item)
          return Failure(:transport_failure)
        end

        case result
        when Dry::Monads::Result
          if result.failure?
            track_failed("transport #{transport} returned failure: #{result.failure}", item)
            Failure(:transport_failure)
          else
            Success()
          end
        when true
          Success()
        else
          track_failed("transport #{transport} returned #{result.inspect}", item)
          Failure(:transport_failure)
        end
      end

      def track_failed(ex_or_msg, item = nil)
        log_error(ex_or_msg, item)

        item&.touch_processed_at
        item&.add_error(ex_or_msg)

        if item.nil?
          report_error(ex_or_msg)
          counters[:fetch_error_counter] += 1
        elsif item.max_retries_exceeded?
          report_error(ex_or_msg, item)
          counters[:error_counter] += 1
          item.failed!
        else
          counters[:retry_counter] += 1
          item.pending!
        end
      end

      def track_successed(item)
        msg = "Successfully delivered #{box_type} item.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{item.log_details.to_json}"
        log_success(msg)

        item.touch_processed_at
        item.delivered!

        counters[:sent_counter] += 1
      end

      def track_discarded(item)
        msg = "Skipped and discarded #{box_type} item.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{item.log_details.to_json}"
        log_success(msg)

        item.touch_processed_at
        item.discarded!

        counters[:discarded_counter] += 1
      end

      def log_error(ex_or_msg, item = nil)
        msg = "Failed processing #{box_type} item with error: #{ex_or_msg}.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{item&.log_details&.to_json}"

        backtrace = ex_or_msg.backtrace.join("\n") if ex_or_msg.respond_to?(:backtrace)

        log_failure(msg, backtrace: backtrace)
      end

      def report_error(ex_or_msg, item = nil)
        Outbox.error_tracker.error(
          ex_or_msg,
          box_name: item_class.box_name,
          item_class: item_class.name,
          item_id: item_id,
          item_details: item&.log_details&.to_json
        )
      end

      def report_metrics(item)
        labels = {type: box_type, name: box_name, partition: item&.partition}

        METRICS_COUNTERS.each do |counter_name|
          Yabeda
            .outbox
            .send(counter_name)
            .increment(labels, by: counters[counter_name])
        end

        track_process_latency(labels) if process_latency

        return unless counters[:sent_counter] > 0

        Yabeda
          .outbox
          .last_sent_event_id
          .set(labels, item_id)
      end

      def counters
        @counters ||= Hash.new(0)
      end

      def track_process_latency(labels)
        Yabeda.outbox.process_latency.measure(labels, process_latency.round(3))
      end
    end
  end
end
