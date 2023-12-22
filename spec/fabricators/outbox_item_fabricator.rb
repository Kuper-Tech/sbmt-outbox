# frozen_string_literal: true

Fabricator(:outbox_item, from: "OutboxItem") do
  payload { "test" }
  event_key { sequence(:event_key) }
  bucket { 0 }
end
