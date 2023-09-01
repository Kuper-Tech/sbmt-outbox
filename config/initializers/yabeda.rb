# frozen_string_literal: true

Yabeda.configure do
  # error_counter retry_counter sent_counter fetch_error_counter discarded_counter
  group :outbox do
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
      buckets: [1, 2.5, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 300, 600, 1200].freeze,
      comment: "A histogram outbox process latency"
  end

  group :box_worker do
    counter :job_counter,
      tags: %i[type name partition worker_number state],
      comment: "The total number of processed jobs"

    counter :job_timeout_counter,
      tags: %i[type name partition_key worker_number],
      comment: "Requeue of a job that occurred while processing the batch"

    counter :job_items_counter,
      tags: %i[type name partition worker_number],
      comment: "The total number of processed items in jobs"

    histogram :job_execution_runtime,
      comment: "A histogram of the job execution time",
      unit: :seconds,
      tags: %i[type name partition worker_number],
      buckets: [0.5, 1, 2.5, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 300, 600]

    histogram :item_execution_runtime,
      comment: "A histogram of the item execution time",
      unit: :seconds,
      tags: %i[type name partition worker_number],
      buckets: [0.5, 1, 2.5, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300]
  end
end
