# frozen_string_literal: true

every "#{Sbmt::Outbox.config.process_items.pooling_interval}s",
  as: "Sbmt::Outbox::ProcessItemsJob",
  overlap: false,
  timeout: "60s" do
  Sbmt::Outbox::ProcessItemsJob.enqueue
end

every "1h", as: "Sbmt::Outbox::DeleteStaleItemsJob", overlap: false, timeout: "60s" do
  Sbmt::Outbox::DeleteStaleItemsJob.enqueue
end
