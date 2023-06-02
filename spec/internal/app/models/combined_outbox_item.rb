# frozen_string_literal: true

class CombinedOutboxItem < Sbmt::Outbox::OutboxItem
  validates :event_name, presence: true
end
