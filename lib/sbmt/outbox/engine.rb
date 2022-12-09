# frozen_string_literal: true

require "rails/engine"

module Sbmt
  module Outbox
    class Engine < Rails::Engine
      isolate_namespace Sbmt::Outbox

      config.outbox = ActiveSupport::OrderedOptions.new.tap do |c|
        c.error_tracker = "Sbmt::Outbox::ErrorTracker"
        c.outbox_item_classes = []
        c.inbox_item_classes = []
        c.paths = []
        c.redis_servers = [ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")]
        c.process_items = ActiveSupport::OrderedOptions.new.tap do |c|
          c.general_timeout = 120
          c.cutoff_timeout = 60
          c.batch_size = 200
        end
        c.worker = ActiveSupport::OrderedOptions.new.tap do |c|
          c.rate_limit = 20
          c.rate_interval = 60
        end
        c.database_switcher = "Sbmt::Outbox::DatabaseSwitcher"
      end

      rake_tasks do
        load "sbmt/outbox/tasks/process_outbox_items.rake"
        load "sbmt/outbox/tasks/retry_failed_outbox_items.rake"
        load "sbmt/outbox/tasks/delete_failed_outbox_items.rake"
      end
    end
  end
end
