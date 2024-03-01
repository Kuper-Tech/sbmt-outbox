# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class RedisQueueSize < Base
          delegate :redis_job_queue_size, to: "Yabeda.box_worker"

          def initialize(redis:, min_size: -1, max_size: 100, delay: 5)
            super()

            @redis = redis
            @min_size = min_size
            @max_size = max_size
            @delay = delay
          end

          def wait(worker_num, poll_task, _task_result)
            # LLEN is O(1)
            queue_size = @redis.call("LLEN", poll_task.redis_queue).to_i
            redis_job_queue_size.set(metric_tags(poll_task), queue_size)

            if queue_size < @min_size || queue_size > @max_size
              sleep(@delay)
              return Success(THROTTLE_STATUS)
            end

            Failure(SKIP_STATUS)
          rescue
            Failure(SKIP_STATUS)
          end
        end
      end
    end
  end
end
