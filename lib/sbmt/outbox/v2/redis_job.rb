# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      class RedisJob
        attr_reader :bucket, :ids

        GENERIC_SEPARATOR = ":"
        IDS_SEPARATOR = ","

        def initialize(bucket, ids)
          @bucket = bucket
          @ids = ids
        end

        def serialize
          "#{bucket}#{GENERIC_SEPARATOR}#{ids.join(IDS_SEPARATOR)}"
        end

        def self.deserialize!(value)
          raise "invalid data type: string is required" unless value.is_a?(String)

          bucket, ids_str, _ = value.split(GENERIC_SEPARATOR)
          raise "invalid data format: bucket or ids are not valid" if bucket.blank? || ids_str.blank?

          ids = ids_str.split(IDS_SEPARATOR).map(&:to_i)
          raise "invalid data format: IDs are empty" if ids.blank?

          new(bucket, ids)
        end
      end
    end
  end
end