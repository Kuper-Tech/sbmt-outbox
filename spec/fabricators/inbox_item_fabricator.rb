# frozen_string_literal: true

Fabricator(:inbox_item, from: "InboxItem") do
  payload { "test" }
  event_key { sequence(:event_key) }
  bucket { 0 }
end
