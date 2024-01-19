# frozen_string_literal: true

FactoryBot.define do
  factory :outbox_item, class: "OutboxItem" do
    payload { "test" }
    sequence(:event_key)
    bucket { 0 }
  end
end
