# frozen_string_literal: true

FactoryBot.define do
  factory :combined_outbox_item, class: "CombinedOutboxItem" do
    payload { "test" }
    event_name { "order_created" }
    sequence(:event_key)
    bucket { 0 }
  end
end
