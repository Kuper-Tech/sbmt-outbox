# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  config.outbox_item_classes << "OutboxItem"
  config.inbox_item_classes << "InboxItem"
  config.dead_letter_classes << "DeadLetter"
  config.paths << Rails.root.join("config/outbox.yml").to_s
end
