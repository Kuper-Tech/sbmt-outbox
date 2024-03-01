# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "sbmt/outbox/v2/redis_job"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class RedisQueueTimeLag < Base
          delegate :redis_job_queue_time_lag, to: "Yabeda.box_worker"

          def initialize(redis:, min_lag: 5, delay: 5)
            super()

            @redis = redis
            @min_lag = min_lag
            @delay = delay
          end

          def wait(worker_num, poll_task, _task_result)
            # LINDEX is O(1) for first/last element
            oldest_job = @redis.call("LINDEX", poll_task.redis_queue, -1)
            return Failure(SKIP_STATUS) if oldest_job.nil?

            job = RedisJob.deserialize!(oldest_job)
            time_lag = Time.current.to_i - job.timestamp

            redis_job_queue_time_lag.set(metric_tags(poll_task), time_lag)

            if time_lag <= @min_lag
              sleep(@delay)
              return Success(THROTTLE_STATUS)
            end

            Failure(SKIP_STATUS)
          rescue
            # noop, just skip any redis / serialization errors
            Failure(SKIP_STATUS)
          end
        end
      end
    end
  end
end
