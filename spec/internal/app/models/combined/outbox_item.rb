# frozen_string_literal: true

module Combined
  class OutboxItem < Sbmt::Outbox::OutboxItem
    self.table_name = :combined_outbox_items

    validates :event_name, presence: true
  end
end
