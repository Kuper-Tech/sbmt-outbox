# frozen_string_literal: true

require "redlock"
require "sbmt/outbox/v2/poller"
require "sbmt/outbox/v2/processor"

module Sbmt
  module Outbox
    module V2
      class Worker
        def initialize(boxes:, poll_tactic: nil, processor_concurrency: nil, poller_partitions_count: nil, poller_threads_count: nil)
          @poller = Poller.new(boxes, throttler_tactic: poll_tactic, threads_count: poller_threads_count, partitions_count: poller_partitions_count)
          @processor = Processor.new(boxes, threads_count: processor_concurrency)
        end

        def start
          start_async

          loop do
            sleep 0.1
            break unless @poller.started && @processor.started
          end
        end

        def start_async
          @poller.start
          @processor.start

          loop do
            sleep(0.1)
            break if ready?
          end
        end

        def stop
          @poller.stop
          @processor.stop
        end

        def ready?
          @poller.ready? && @processor.ready?
        end

        def alive?
          return false unless ready?

          @poller.alive?(@poller.lock_timeout) && @processor.alive?(@processor.lock_timeout)
        end
      end
    end
  end
end
