# frozen_string_literal: true

require "rails"
require "dry-initializer"
require "dry-monads"
require "dry/monads/do"
require "yabeda"
require "exponential_backoff"
require "cutoff"
require "http_health_check"
require "redis-client"
require "connection_pool"

begin
  require "sentry-rails"

  require_relative "outbox/middleware/sentry/tracing_batch_process_middleware"
  require_relative "outbox/middleware/sentry/tracing_item_process_middleware"
rescue LoadError
  # optional dependency
end

begin
  require_relative "outbox/instrumentation/open_telemetry_loader"
rescue LoadError
  # optional dependency
end

require_relative "outbox/version"
require_relative "outbox/errors"
require_relative "outbox/error_tracker"
require_relative "outbox/logger"
require_relative "outbox/database_switcher"
require_relative "outbox/engine"
require_relative "outbox/middleware/builder"
require_relative "outbox/middleware/runner"
require_relative "outbox/probes/probe"
require_relative "outbox/redis_client_factory"

module Sbmt
  module Outbox
    class << self
      attr_accessor :current_worker
    end

    module_function

    def config
      @config ||= Rails.application.config.outbox
    end

    def logger
      @logger ||= Sbmt::Outbox::Logger.new
    end

    def poller_config
      @poller_config ||= config.poller
    end

    def active_record_base_class
      @active_record_base_class ||= config.active_record_base_class.safe_constantize || ActiveRecord::Base
    end

    def active_job_base_class
      @active_job_base_class ||= config.active_job_base_class.safe_constantize || ActiveJob::Base
    end

    def error_tracker
      @error_tracker ||= config.error_tracker.constantize
    end

    def database_switcher
      @database_switcher ||= config.database_switcher.constantize
    end

    def outbox_item_classes
      @outbox_item_classes ||= if config.outbox_item_classes.empty?
        (yaml_config[:outbox_items] || {}).keys.map { |name| name.camelize.constantize }
      else
        config.outbox_item_classes.map(&:constantize)
      end
    end

    def inbox_item_classes
      @inbox_item_classes ||= if config.inbox_item_classes.empty?
        (yaml_config[:inbox_items] || {}).keys.map { |name| name.camelize.constantize }
      else
        config.inbox_item_classes.map(&:constantize)
      end
    end

    def item_classes
      @item_classes ||= outbox_item_classes + inbox_item_classes
    end

    def item_classes_by_name
      @item_classes_by_name ||= item_classes.index_by(&:box_name)
    end

    def yaml_config
      return @yaml_config if defined?(@yaml_config)

      paths = if config.paths.empty?
        [Rails.root.join("config/outbox.yml").to_s]
      else
        config.paths
      end

      @yaml_config = paths.each_with_object({}.with_indifferent_access) do |path, memo|
        memo.deep_merge!(
          load_yaml(path)
        )
      end
    end

    def load_yaml(path)
      data = if Gem::Version.new(Psych::VERSION) >= Gem::Version.new("4.0.0")
        YAML.safe_load(ERB.new(File.read(path)).result, aliases: true)
      else
        YAML.safe_load(ERB.new(File.read(path)).result, [], [], true)
      end

      data
        .with_indifferent_access
        .fetch(Rails.env, {})
    end

    def batch_process_middlewares
      @batch_process_middlewares ||= config.batch_process_middlewares.map(&:constantize)
    end

    def item_process_middlewares
      @item_process_middlewares ||= config.item_process_middlewares.map(&:constantize)
    end

    def create_item_middlewares
      @create_item_middlewares ||= config.create_item_middlewares.map(&:constantize)
    end
  end
end
