# frozen_string_literal: true

every "10s", as: "Sbmt::Outbox::ProcessItemsJob", overlap: false, timeout: "5s" do
  Sbmt::Outbox::ProcessItemsJob.enqueue
end
