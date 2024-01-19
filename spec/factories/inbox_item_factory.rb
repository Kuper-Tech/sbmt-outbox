# frozen_string_literal: true

FactoryBot.define do
  factory :inbox_item, class: "InboxItem" do
    payload { "test" }
    sequence(:event_key)
    bucket { 0 }
  end
end
