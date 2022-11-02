# frozen_string_literal: true

Yabeda.configure do
  box_counters = -> do
    counter :sent_counter,
      tags: %i[name],
      comment: "The total number of processed messages"

    counter :error_counter,
      tags: %i[name],
      comment: "Errors (excepting retries) that occurred while processing messages"

    counter :retry_counter,
      tags: %i[name],
      comment: "Retries that occurred while processing messages"

    counter :discarded_counter,
      tags: %i[name],
      comment: "The total number of discarded messages"

    counter :requeue_counter,
      tags: %i[name partition_key],
      comment: "Requeue of a sidekiq job that occurred while processing outbox messages"

    gauge :last_stored_event_id,
      tags: %i[name],
      comment: "The ID of the last stored event"

    gauge :last_sent_event_id,
      tags: %i[name],
      comment: "The ID of the last sent event. " \
                "If the message order is not preserved, the value may be inaccurate"
  end

  group :outbox, &box_counters
  group :inbox, &box_counters

  group :box_worker do
    counter :job_counter,
      tags: %i[type name partition worker_number state],
      comment: "The total number of processed messages"
  end

  group :dead_letters do
    counter :error_counter,
      tags: %i[name topic],
      comment: "Errors that occurred while consuming messages"
  end
end
