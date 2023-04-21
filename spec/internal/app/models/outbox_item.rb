# frozen_string_literal: true

class OutboxItem < Sbmt::Outbox::OutboxItem
  validates :event_name, :proto_payload, presence: true
end
