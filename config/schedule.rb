# frozen_string_literal: true

every "#{Sbmt::Outbox.config.process_items.pooling_interval}s",
  as: "Sbmt::Outbox::ProcessItemsJob",
  overlap: false,
  timeout: "60s" do
  Sbmt::Outbox::ProcessItemsJob.enqueue
end

every "#{Sbmt::Outbox.config.process_items.pooling_interval}s",
  as: "Sbmt::Outbox::ProcessInboxItemsJob",
  overlap: false,
  timeout: "60s" do
  Sbmt::Outbox::ProcessInboxItemsJob.enqueue
end

every "10m", as: "Sbmt::Outbox::DeleteStaleOutboxItemsJob", overlap: false, timeout: "60s" do
  Sbmt::Outbox::DeleteStaleOutboxItemsJob.enqueue
end

every "10m", as: "Sbmt::Outbox::DeleteStaleInboxItemsJob", overlap: false, timeout: "60s" do
  Sbmt::Outbox::DeleteStaleInboxItemsJob.enqueue
end
