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
        c.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}
        c.process_items = ActiveSupport::OrderedOptions.new.tap do |c|
          c.general_timeout = 120
          c.cutoff_timeout = 60
          c.batch_size = 200
        end
        c.worker = ActiveSupport::OrderedOptions.new.tap do |c|
          c.rate_limit = 20
          c.rate_interval = 60
          c.shuffle_jobs = true
        end
        c.database_switcher = "Sbmt::Outbox::DatabaseSwitcher"
        c.batch_process_middlewares = []
        c.item_process_middlewares = []

        if defined?(::Sentry)
          c.batch_process_middlewares.push("Sbmt::Outbox::Middleware::Sentry::TracingBatchProcessMiddleware")
          c.item_process_middlewares.push("Sbmt::Outbox::Middleware::Sentry::TracingItemProcessMiddleware")
        end

        def c.redis_servers=(val)
          val = val.first

          if val.is_a?(String)
            self.redis = {url: val}
          elsif val.respond_to?(:_client)
            conf = val._client.config
            self.redis = {url: conf.server_url, username: conf.username, password: conf.password}
          else
            raise ArgumentError, "Outbox `redis_servers=` config option is deprecated. Please use `redis=` with a Hash"
          end

          warn "🔥 Outbox `redis_servers=` config option is deprecated. Please use `redis=` with a Hash. Called from #{caller(1..1).first}"
        end
      end

      rake_tasks do
        load "sbmt/outbox/tasks/process_outbox_items.rake"
        load "sbmt/outbox/tasks/retry_failed_outbox_items.rake"
        load "sbmt/outbox/tasks/delete_failed_outbox_items.rake"
      end
    end
  end
end
