# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      class RedisJob
        attr_reader :bucket, :timestamp, :ids

        GENERIC_SEPARATOR = ":"
        IDS_SEPARATOR = ","

        def initialize(bucket, ids, timestamp = Time.current.to_i)
          @bucket = bucket
          @ids = ids
          @timestamp = timestamp
        end

        def to_s
          serialize
        end

        def serialize
          [bucket, timestamp, ids.join(IDS_SEPARATOR)].join(GENERIC_SEPARATOR)
        end

        def self.deserialize!(value)
          raise "invalid data type: string is required" unless value.is_a?(String)

          bucket, ts_utc, ids_str, _ = value.split(GENERIC_SEPARATOR)
          raise "invalid data format: bucket or ids are not valid" if bucket.blank? || ts_utc.blank? || ids_str.blank?

          ts = ts_utc.to_i

          ids = ids_str.split(IDS_SEPARATOR).map(&:to_i)
          raise "invalid data format: IDs are empty" if ids.blank?

          new(bucket, ids, ts)
        end
      end
    end
  end
end
