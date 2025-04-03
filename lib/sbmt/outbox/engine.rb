# frozen_string_literal: true

require "rails/engine"

module Sbmt
  module Outbox
    class Engine < Rails::Engine
      isolate_namespace Sbmt::Outbox

      config.outbox = ActiveSupport::OrderedOptions.new.tap do |c|
        c.active_record_base_class = "ApplicationRecord"
        c.active_job_base_class = "ApplicationJob"
        c.action_controller_api_base_class = "ActionController::API"
        # We cannot use ApplicationController because often it could be inherited from ActionController::API
        c.action_controller_base_class = "ActionController::Base"
        c.error_tracker = "Sbmt::Outbox::ErrorTracker"
        c.outbox_item_classes = []
        c.inbox_item_classes = []
        c.paths = []
        c.disposable_transports = false
        c.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}
        c.ui = ActiveSupport::OrderedOptions.new.tap do |c|
          c.serve_local = false
          c.local_endpoint = "http://localhost:5173"
          c.cdn_url = "https://cdn.jsdelivr.net/npm/sbmt-outbox-ui@0.0.8/dist/assets/index.js"
        end
        c.process_items = ActiveSupport::OrderedOptions.new.tap do |c|
          c.general_timeout = 180
          c.cutoff_timeout = 90
          c.batch_size = 200
        end

        # worker v2
        c.poller = ActiveSupport::OrderedOptions.new.tap do |pc|
          pc.concurrency = 6
          pc.threads_count = 2
          pc.general_timeout = 60
          pc.regular_items_batch_size = 200
          pc.retryable_items_batch_size = 100

          pc.tactic = "default"
          pc.rate_limit = 60
          pc.rate_interval = 60
          pc.min_queue_size = 10
          pc.max_queue_size = 100
          pc.min_queue_timelag = 5
          pc.queue_delay = 0.1
        end
        c.processor = ActiveSupport::OrderedOptions.new.tap do |pc|
          pc.threads_count = 4
          pc.general_timeout = 180
          pc.cutoff_timeout = 90
          pc.brpop_delay = 1
        end

        c.database_switcher = "Sbmt::Outbox::DatabaseSwitcher"
        c.batch_process_middlewares = []
        c.item_process_middlewares = []
        c.create_item_middlewares = []
        c.create_batch_middlewares = []
        c.polling_item_middlewares = []

        if defined?(::Sentry)
          c.batch_process_middlewares.push("Sbmt::Outbox::Middleware::Sentry::TracingBatchProcessMiddleware")
          c.item_process_middlewares.push("Sbmt::Outbox::Middleware::Sentry::TracingItemProcessMiddleware")
        end

        if defined?(ActiveSupport::ExecutionContext)
          require_relative "middleware/execution_context/context_item_process_middleware"
          c.item_process_middlewares.push("Sbmt::Outbox::Middleware::ExecutionContext::ContextItemProcessMiddleware")
        end
      end

      rake_tasks do
        load "sbmt/outbox/tasks/retry_failed_items.rake"
        load "sbmt/outbox/tasks/delete_failed_items.rake"
        load "sbmt/outbox/tasks/delete_items.rake"
        load "sbmt/outbox/tasks/update_status_items.rake"
      end
    end
  end
end
