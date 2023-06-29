# frozen_string_literal: true

require "ruby2_keywords"
require "rails"
require "sidekiq"
require "sidekiq-unique-jobs"
require "dry-initializer"
require "dry-monads"
require "dry/monads/do"
require "schked"
require "yabeda"
require "after_commit_everywhere"
require "exponential_backoff"
require "cutoff"
require "http_health_check"

begin
  require "sentry-rails"

  require_relative "outbox/middleware/sentry/tracing_batch_process_middleware"
  require_relative "outbox/middleware/sentry/tracing_item_process_middleware"
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

    def error_tracker
      @error_tracker ||= config.error_tracker.constantize
    end

    def database_switcher
      @database_switcher ||= config.database_switcher.constantize
    end

    def outbox_item_classes
      @outbox_item_classes ||= config.outbox_item_classes.map(&:constantize)
    end

    def inbox_item_classes
      @inbox_item_classes ||= config.inbox_item_classes.map(&:constantize)
    end

    def item_classes
      @item_classes ||= outbox_item_classes + inbox_item_classes
    end

    def item_classes_by_name
      @item_classes_by_name ||= item_classes.index_by(&:box_name)
    end

    def yaml_config
      @yaml_config ||= config.paths.each_with_object({}.with_indifferent_access) do |path, memo|
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
  end
end
