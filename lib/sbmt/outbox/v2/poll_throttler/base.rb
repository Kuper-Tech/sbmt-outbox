# frozen_string_literal: true

module Sbmt
  module Outbox
    module V2
      module PollThrottler
        class Base < Outbox::DryInteractor
          delegate :poll_throttling_counter, :poll_throttling_runtime, to: "Yabeda.box_worker"

          THROTTLE_STATUS = "throttle"
          SKIP_STATUS = "skip"

          def call(worker_num, poll_task, task_result)
            with_metrics(poll_task) do
              wait(worker_num, poll_task, task_result)
            end
          end

          def wait(_worker_num, _poll_task, _task_result)
            raise NotImplementedError, "Implement #wait for Sbmt::Outbox::PollThrottler::Base"
          end

          private

          def with_metrics(poll_task, &block)
            tags = metric_tags(poll_task)

            poll_throttling_runtime.measure(tags) do
              result = yield

              poll_throttling_counter.increment(tags.merge(status: result.value_or(result.failure)), by: 1)
              result
            end
          end

          def metric_tags(poll_task)
            poll_task.yabeda_labels.merge(throttler: self.class.name)
          end
        end
      end
    end
  end
end
