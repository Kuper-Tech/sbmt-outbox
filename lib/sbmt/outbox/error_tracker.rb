# frozen_string_literal: true

module Sbmt
  module Outbox
    module ErrorTracker
      extend self

      def error(arr, _params = {})
        Rails.logger.error(arr)
      end

      def warning(arr, _params = {})
        Rails.logger.warn("sbmt-outbox") do
          arr.to_s
        end
      end

      private

      def format_msg(arr, params)
        if arr.respond_to?(:message)
          "#{arr.message}, params: #{params.inspect}"
        else
          "#{arr}, params: #{params.inspect}"
        end
      end
    end
  end
end
