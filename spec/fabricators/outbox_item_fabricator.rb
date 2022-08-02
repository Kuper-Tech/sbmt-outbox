# frozen_string_literal: true

Fabricator(:outbox_item, from: "OutboxItem") do
  proto_payload "test"
end
