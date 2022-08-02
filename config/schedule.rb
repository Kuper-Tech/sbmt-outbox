# frozen_string_literal: true

every "10s", as: "Sbmt::Outbox::ProcessItemsJob" do
  Sbmt::Outbox::ProcessItemsJob.perform_async
end
