# frozen_string_literal: true

require "sbmt/outbox/metrics/utils"
require "sbmt/outbox/v2/redis_item_meta"

module Sbmt
  module Outbox
    class ProcessItem < Sbmt::Outbox::DryInteractor
      param :item_class, reader: :private
      param :item_id, reader: :private
      option :worker_version, reader: :private, optional: true, default: -> { 1 }
      option :cache_ttl_sec, reader: :private, optional: true, default: -> { 5 * 60 }
      option :redis, reader: :private, optional: true, default: -> {}

      METRICS_COUNTERS = %i[error_counter retry_counter sent_counter fetch_error_counter discarded_counter].freeze

      delegate :log_success, :log_info, :log_failure, :log_debug, to: "Sbmt::Outbox.logger"
      delegate :item_process_middlewares, to: "Sbmt::Outbox"
      delegate :box_type, :box_name, :owner, to: :item_class

      attr_accessor :process_latency, :retry_latency

      def call
        log_success(
          "Start processing #{box_type} item.\n" \
          "Record: #{item_class.name}##{item_id}"
        )

        item = nil

        item_class.transaction do
          item = yield fetch_item_and_lock_for_update

          cached_item = fetch_redis_item_meta(redis_item_key(item_id))
          if cached_retries_exceeded?(cached_item)
            msg = "max retries exceeded: marking item as failed based on cached data: #{cached_item}"
            item.set_errors_count(cached_item.errors_count)
            track_failed(msg, item)
            next Failure(msg)
          end

          if cached_greater_errors_count?(item, cached_item)
            log_failure("inconsistent item: cached_errors_count:#{cached_item.errors_count} > db_errors_count:#{item.errors_count}: setting errors_count based on cached data:#{cached_item}")
            item.set_errors_count(cached_item.errors_count)
          end

          if item.processed_at?
            self.retry_latency = Time.current - item.created_at
            item.config.retry_strategies.each do |retry_strategy|
              yield check_retry_strategy(item, retry_strategy)
            end
          else
            self.process_latency = Time.current - item.created_at
          end

          middlewares = Middleware::Builder.new(item_process_middlewares)
          payload = yield build_payload(item)
          transports = yield fetch_transports(item)

          middlewares.call(item) do
            transports.each do |transport|
              yield process_item(transport, item, payload)
            end

            track_successed(item)

            Success(item)
          end
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

      def cached_retries_exceeded?(cached_item)
        return false unless cached_item

        item_class.max_retries_exceeded?(cached_item.errors_count)
      end

      def cached_greater_errors_count?(db_item, cached_item)
        return false unless cached_item

        cached_item.errors_count > db_item.errors_count
      end

      def fetch_redis_item_meta(redis_key)
        return if worker_version < 2

        data = redis.call("GET", redis_key)
        return if data.blank?

        Sbmt::Outbox::V2::RedisItemMeta.deserialize!(data)
      rescue => ex
        log_debug("error while fetching redis meta: #{ex.message}")
        nil
      end

      def set_redis_item_meta(item, ex)
        return if worker_version < 2
        return if item.nil?

        redis_key = redis_item_key(item.id)
        error_msg = format_exception_error(ex, extract_cause: false)
        data = Sbmt::Outbox::V2::RedisItemMeta.new(errors_count: item.errors_count, error_msg: error_msg)
        redis.call("SET", redis_key, data.to_s, "EX", cache_ttl_sec)
      rescue => ex
        log_debug("error while fetching redis meta: #{ex.message}")
        nil
      end

      def redis_item_key(item_id)
        "#{box_type}:#{item_class.box_name}:#{item_id}"
      end

      def fetch_item_and_lock_for_update
        item = item_class
          .lock("FOR UPDATE")
          .find_by(id: item_id)

        unless item
          track_failed("not found")
          return Failure(:not_found)
        end

        unless item.for_processing?
          log_info("already processed")
          counters[:fetch_error_counter] += 1
          return Failure(:already_processed)
        end

        Success(item)
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
          track_failed("retry strategy returned unknown failure: #{result.failure}")
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
          Success(item.payload)
        end
      end

      def fetch_transports(item)
        transports = item.transports
        return Success(transports) if transports.present?

        track_failed("missing transports", item)
        Failure(:missing_transports)
      end

      # rubocop:disable Metrics/MethodLength
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
        when false
          track_failed("transport #{transport} returned #{result.inspect}", item)
          Failure(:transport_failure)
        else
          Success()
        end
      end
      # rubocop:enable Metrics/MethodLength

      def track_failed(ex_or_msg, item = nil)
        log_processing_error(ex_or_msg, item)

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
      rescue => e
        set_redis_item_meta(item, e)
        log_error_handling_error(e, item)
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

      def log_processing_error(ex_or_msg, item = nil)
        text = format_exception_error(ex_or_msg)

        msg = "Failed processing #{box_type} item with error: #{text}.\n" \
              "Record: #{item_class.name}##{item_id}.\n" \
              "#{item&.log_details&.to_json}"

        log_failure(msg, stacktrace: format_backtrace(ex_or_msg))
      end

      def log_error_handling_error(handling_error, item = nil)
        text = format_exception_error(handling_error, extract_cause: false)

        msg = "Could not persist status of failed #{box_type} item due to error: #{text}.\n" \
          "Record: #{item_class.name}##{item_id}.\n" \
          "#{item&.log_details&.to_json}"

        log_failure(msg, stacktrace: format_backtrace(handling_error))
      end

      def format_exception_error(e, extract_cause: true)
        text = if extract_cause && e.respond_to?(:cause) && !e.cause.nil?
          "#{format_exception_error(e.cause)}. "
        else
          ""
        end

        if e.respond_to?(:message)
          "#{text}#{e.class.name} #{e.message}"
        else
          "#{text}#{e}"
        end
      end

      def format_backtrace(e)
        if e.respond_to?(:backtrace) && !e.backtrace.nil?
          e.backtrace.join("\n")
        end
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
        labels = labels_for(item)

        METRICS_COUNTERS.each do |counter_name|
          Yabeda
            .outbox
            .send(counter_name)
            .increment(labels, by: counters[counter_name])
        end

        track_process_latency(labels) if process_latency
        track_retry_latency(labels) if retry_latency

        return unless counters[:sent_counter].positive?

        Yabeda
          .outbox
          .last_sent_event_id
          .set(labels, item_id)
      end

      def labels_for(item)
        {worker_version: worker_version, type: box_type, name: Sbmt::Outbox::Metrics::Utils.metric_safe(box_name), owner: owner, partition: item&.partition}
      end

      def counters
        @counters ||= Hash.new(0)
      end

      def track_process_latency(labels)
        Yabeda.outbox.process_latency.measure(labels, process_latency.round(3))
      end

      def track_retry_latency(labels)
        Yabeda.outbox.retry_latency.measure(labels, retry_latency.round(3))
      end
    end
  end
end
