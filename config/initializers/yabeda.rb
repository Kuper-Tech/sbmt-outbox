# frozen_string_literal: true

Yabeda.configure do
  group :outbox do
    counter :sent_counter,
      tags: %i[name],
      comment: "The total number of sent events"

    counter :error_counter,
      tags: %i[name],
      comment: "Errors (excepting retries) that occurred while processing outbox messages"

    counter :retry_counter,
      tags: %i[name],
      comment: "Retries that occurred while processing outbox messages"

    gauge :last_stored_event_id,
      tags: %i[name],
      comment: "The ID of the last stored event"

    gauge :last_sent_event_id,
      tags: %i[name],
      comment: "The ID of the last sent event. " \
               "If the message order is not preserved, the value may be inaccurate"
  end

  group :dead_letters do
    counter :error_counter,
      tags: %i[name topic],
      comment: "Errors that occurred while consuming messages"
  end
end
