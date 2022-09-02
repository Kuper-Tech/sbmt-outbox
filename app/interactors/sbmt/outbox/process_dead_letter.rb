# frozen_string_literal: true

module Sbmt
  module Outbox
    class ProcessDeadLetter < Sbmt::Outbox::DryInteractor
      TIMEOUT = ENV.fetch("SBMT_OUTBOX__APP__PROCESS_DEAD_LETTER_TIMEOUT", 30).to_i

      param :letter_class, reader: :private
      param :letter_id, reader: :private
      option :timeout, reader: :private, default: -> { TIMEOUT }

      delegate :log_success, :log_failure, to: "Sbmt::Outbox.logger"

      def call
        letter = nil

        letter_class.transaction do
          Timeout.timeout(timeout) do
            letter = yield fetch_letter
            yield process_letter(letter)

            letter.delete

            track_successed(letter)
            Success()
          end
        rescue Dry::Monads::Do::Halt => e
          e.result
        rescue Timeout::Error
          track_failed("execution expired", letter)
        end
      end

      private

      def fetch_letter
        letter = letter_class
          .lock("FOR UPDATE")
          .find_by(id: letter_id)
        return Success(letter) if letter

        track_fatal("not found")
      end

      def process_letter(letter)
        metadata = extract_metadata(letter)

        result = letter.handler.call(letter.payload, metadata)

        return track_failed(result.failure, letter) if result.failure?

        Success()
      end

      def extract_metadata(letter)
        headers = letter.metadata&.dig("headers")
        sequence_id = headers&.dig(Sbmt::Outbox::Item::SEQUENCE_HEADER_NAME)
        sequence_id = Integer(sequence_id) if sequence_id.present?

        event_timestamp = headers&.dig(Sbmt::Outbox::Item::EVENT_TIME_HEADER_NAME)
        event_timestamp = Time.zone.parse(event_timestamp) if event_timestamp.present?

        {
          sequence_id: sequence_id,
          event_timestamp: event_timestamp
        }
      end

      def track_failed(error, letter)
        error_message = "#{format_error_message(error)} #{letter.log_details.to_json}"

        log_failure(error_message, outbox_name: letter.outbox_name)

        track_error_exception(error_message)

        Failure(error_message)
      end

      def track_fatal(error)
        error_message = format_error_message(error)
        log_failure(error_message, outbox_name: "none")
        track_error_exception(error_message)

        Failure(error_message)
      end

      def track_successed(letter)
        msg = "Dead letter successfully processed and deleted. " \
              "Record: #{letter_class.name}##{letter_id} #{letter.log_details.to_json}"
        log_success(msg, outbox_name: letter.outbox_name)
      end

      def format_error_message(error)
        failure = error.respond_to?(:failure) ? error.failure : error
        "Dead letter failed with error: #{failure}. " \
        "Record: #{letter_class.name}##{letter_id}"
      end

      def track_error_exception(error_message)
        error = ProcessDeadLetterError.new(error_message)
        Outbox.error_tracker.error(error)
      end
    end
  end
end
