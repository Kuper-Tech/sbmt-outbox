# frozen_string_literal: true

class InboxItem < Sbmt::Outbox::InboxItem
  validates :event_name, :proto_payload, presence: true
end
