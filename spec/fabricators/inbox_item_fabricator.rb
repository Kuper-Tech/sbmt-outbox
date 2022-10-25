# frozen_string_literal: true

Fabricator(:inbox_item, from: "InboxItem") do
  proto_payload { "test" }
  event_name { "order_created" }
  event_key { sequence(:event_key) }
end
