# frozen_string_literal: true

Yabeda.configure do
  # error_counter retry_counter sent_counter fetch_error_counter discarded_counter
  group :outbox do
    default_tag(:worker_version, 1)

    counter :created_counter,
      tags: %i[type name partition owner],
      comment: "The total number of created messages"

    counter :sent_counter,
      tags: %i[type name partition owner],
      comment: "The total number of processed messages"

    counter :error_counter,
      tags: %i[type name partition owner],
      comment: "Errors (excepting retries) that occurred while processing messages"

    counter :retry_counter,
      tags: %i[type name partition owner],
      comment: "Retries that occurred while processing messages"

    counter :discarded_counter,
      tags: %i[type name partition owner],
      comment: "The total number of discarded messages"

    counter :fetch_error_counter,
      tags: %i[type name partition owner],
      comment: "Errors that occurred while fetching messages"

    gauge :last_stored_event_id,
      tags: %i[type name partition owner],
      comment: "The ID of the last stored event"

    gauge :last_sent_event_id,
      tags: %i[type name partition owner],
      comment: "The ID of the last sent event. " \
                "If the message order is not preserved, the value may be inaccurate"

    histogram :process_latency,
      tags: %i[type name partition owner],
      unit: :seconds,
      buckets: [0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60, 300].freeze,
      comment: "A histogram outbox process latency"

    histogram :delete_latency,
      tags: %i[box_type box_name],
      unit: :seconds,
      buckets: [0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 30].freeze,
      comment: "A histogram for outbox/inbox deletion latency"

    histogram :retry_latency,
      tags: %i[type name partition owner],
      unit: :seconds,
      buckets: [1, 10, 20, 50, 120, 300, 900, 1800, 3600].freeze,
      comment: "A histogram outbox retry latency"

    counter :deleted_counter,
      tags: %i[box_type box_name],
      comment: "A counter for the number of deleted outbox/inbox items"
  end

  group :box_worker do
    default_tag(:worker_version, 1)
    default_tag(:worker_name, "worker")

    counter :job_counter,
      tags: %i[type name partition state owner],
      comment: "The total number of processed jobs"

    counter :job_timeout_counter,
      tags: %i[type name partition_key],
      comment: "Requeue of a job that occurred while processing the batch"

    counter :job_items_counter,
      tags: %i[type name partition],
      comment: "The total number of processed items in jobs"

    histogram :job_execution_runtime,
      comment: "A histogram of the job execution time",
      unit: :seconds,
      tags: %i[type name partition],
      buckets: [0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60, 300]

    histogram :item_execution_runtime,
      comment: "A histogram of the item execution time",
      unit: :seconds,
      tags: %i[type name partition],
      buckets: [0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60, 300]

    counter :batches_per_poll_counter,
      tags: %i[type name partition],
      comment: "The total number of poll batches per poll"

    gauge :redis_job_queue_size,
      tags: %i[type name partition],
      comment: "The total size of redis job queue"

    gauge :redis_job_queue_time_lag,
      tags: %i[type name partition],
      comment: "The total time lag of redis job queue"

    counter :poll_throttling_counter,
      tags: %i[type name partition throttler status],
      comment: "The total number of poll throttlings"

    histogram :poll_throttling_runtime,
      comment: "A histogram of the poll throttling time",
      unit: :seconds,
      tags: %i[type name partition throttler],
      buckets: [0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60, 300]
  end
end
