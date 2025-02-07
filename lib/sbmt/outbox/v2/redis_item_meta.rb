# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      class RedisItemMeta
        attr_reader :version, :timestamp, :errors_count, :error_msg

        CURRENT_VERSION = 1
        MAX_ERROR_LEN = 200

        def initialize(errors_count:, error_msg:, timestamp: Time.current.to_i, version: CURRENT_VERSION)
          @errors_count = errors_count
          @error_msg = error_msg
          @timestamp = timestamp
          @version = version
        end

        def to_s
          serialize
        end

        def serialize
          JSON.generate({
            version: version,
            timestamp: timestamp,
            errors_count: errors_count,
            error_msg: error_msg.slice(0, MAX_ERROR_LEN)
          })
        end

        def self.deserialize!(value)
          raise "invalid data type: string is required" unless value.is_a?(String)

          data = JSON.parse!(value, max_nesting: 1)
          new(
            version: data["version"],
            timestamp: data["timestamp"].to_i,
            errors_count: data["errors_count"].to_i,
            error_msg: data["error_msg"]
          )
        end
      end
    end
  end
end
