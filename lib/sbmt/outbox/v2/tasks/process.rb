# frozen_string_literal: true

require "sbmt/outbox/v2/tasks/base"

module Sbmt
  module Outbox
    module V2
      module Tasks
        class Process < Base
          attr_reader :partition, :bucket, :ids, :resource_key, :resource_path

          def initialize(item_class:, worker_name:, bucket:, ids:)
            super(item_class: item_class, worker_name: worker_name)

            @bucket = bucket
            @ids = ids

            @resource_key = "#{item_class.box_name}:#{bucket}"
            @resource_path = "sbmt:outbox:#{worker_name}:#{resource_key}"

            @log_tags = log_tags.merge(bucket: bucket)
          end

          def to_s
            resource_path
          end
        end
      end
    end
  end
end
