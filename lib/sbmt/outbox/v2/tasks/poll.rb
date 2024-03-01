# frozen_string_literal: true

require "sbmt/outbox/v2/tasks/base"

module Sbmt
  module Outbox
    module V2
      module Tasks
        class Poll < Base
          attr_reader :partition, :buckets, :resource_key, :resource_path, :redis_queue

          def initialize(item_class:, worker_name:, partition:, buckets:)
            super(item_class: item_class, worker_name: worker_name)

            @partition = partition
            @buckets = buckets

            @resource_key = "#{item_class.box_name}:#{partition}"
            @resource_path = "sbmt:outbox:#{worker_name}:#{resource_key}"
            @redis_queue = "#{item_class.box_name}:job_queue"

            @log_tags = log_tags.merge(box_partition: partition)

            @yabeda_labels = yabeda_labels.merge(partition: partition)
          end

          def to_s
            resource_path
          end
        end
      end
    end
  end
end
