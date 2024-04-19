# frozen_string_literal: true

require "sbmt/outbox/v2/poll_throttler/base"
require "sbmt/outbox/v2/poll_throttler/composite"
require "sbmt/outbox/v2/poll_throttler/rate_limited"
require "sbmt/outbox/v2/poll_throttler/fixed_delay"
require "sbmt/outbox/v2/poll_throttler/noop"
require "sbmt/outbox/v2/poll_throttler/redis_queue_size"
require "sbmt/outbox/v2/poll_throttler/redis_queue_time_lag"
require "sbmt/outbox/v2/poll_throttler/paused_box"

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        POLL_TACTICS = %w[noop default low-priority aggressive]

        def self.build(tactic, redis, poller_config)
          raise "WARN: invalid poller poll tactic provided: #{tactic}, available options: #{POLL_TACTICS}" unless POLL_TACTICS.include?(tactic)

          # no-op, for testing purposes
          return Noop.new if tactic == "noop"

          if tactic == "default"
            # composite of RateLimited & RedisQueueSize (upper bound only)
            # optimal polling performance for most cases
            Composite.new(throttlers: [
              PausedBox.new,
              RedisQueueSize.new(redis: redis, max_size: poller_config.max_queue_size, delay: poller_config.queue_delay),
              RateLimited.new(limit: poller_config.rate_limit, interval: poller_config.rate_interval)
            ])
          elsif tactic == "low-priority"
            # composite of RateLimited & RedisQueueSize (with lower & upper bounds) & RedisQueueTimeLag,
            # delays polling depending on min job queue size threshold
            # and also by min redis queue oldest item lag
            # optimal polling performance for low-intensity data flow
            Composite.new(throttlers: [
              PausedBox.new,
              RedisQueueSize.new(redis: redis, min_size: poller_config.min_queue_size, max_size: poller_config.max_queue_size, delay: poller_config.queue_delay),
              RedisQueueTimeLag.new(redis: redis, min_lag: poller_config.min_queue_timelag, delay: poller_config.queue_delay),
              RateLimited.new(limit: poller_config.rate_limit, interval: poller_config.rate_interval)
            ])
          elsif tactic == "aggressive"
            # throttles only by max job queue size, max polling performance
            # optimal polling performance for high-intensity data flow
            Composite.new(throttlers: [
              PausedBox.new,
              RedisQueueSize.new(redis: redis, max_size: poller_config.max_queue_size, delay: poller_config.queue_delay)
            ])
          end
        end
      end
    end
  end
end
