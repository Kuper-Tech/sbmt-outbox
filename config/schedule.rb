# frozen_string_literal: true

every "10m", as: "Sbmt::Outbox::DeleteStaleOutboxItemsJob", overlap: false, timeout: "60s" do
  Sbmt::Outbox::DeleteStaleOutboxItemsJob.enqueue
end

every "10m", as: "Sbmt::Outbox::DeleteStaleInboxItemsJob", overlap: false, timeout: "60s" do
  Sbmt::Outbox::DeleteStaleInboxItemsJob.enqueue
end
