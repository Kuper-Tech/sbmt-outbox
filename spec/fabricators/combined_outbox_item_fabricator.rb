# frozen_string_literal: true

Fabricator(:combined_outbox_item, from: "CombinedOutboxItem") do
  proto_payload { "test" }
  event_name { "order_created" }
  event_key { sequence(:event_key) }
  bucket { 0 }
end
