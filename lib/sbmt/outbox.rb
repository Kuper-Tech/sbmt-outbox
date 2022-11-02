# frozen_string_literal: true

require "ruby2_keywords"
require "rails"
require "sidekiq"
require "sidekiq-unique-jobs"
require "dry-initializer"
require "dry-monads"
require "dry/monads/do"
require "schked"
require "kafka"
require "delivery_boy"
require "waterdrop"
require "yabeda"
require "after_commit_everywhere"
require "exponential_backoff"
require "cutoff"

require_relative "outbox/version"
require_relative "outbox/errors"
require_relative "outbox/error_tracker"
require_relative "outbox/logger"
require_relative "outbox/kafka_producers/delivery_boy"
require_relative "outbox/kafka_producers/async_producer"
require_relative "outbox/kafka_producers/sync_producer"
require_relative "outbox/engine"

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

    def outbox_item_classes
      @outbox_item_classes ||= config.item_classes.map(&:constantize) + config.outbox_item_classes.map(&:constantize)
    end

    def schked_ignore_outbox_item_classes
      @schked_ignore_outbox_item_classes ||= config.schked_ignore_outbox_item_classes.map(&:constantize)
    end

    alias_method :item_classes, :outbox_item_classes

    def inbox_item_classes
      @item_classes ||= config.inbox_item_classes.map(&:constantize)
    end

    def schked_ignore_inbox_item_classes
      @schked_ignore_inbox_item_classes ||= config.schked_ignore_inbox_item_classes.map(&:constantize)
    end

    def item_classes_by_name
      @item_classes_by_name ||= (outbox_item_classes + inbox_item_classes).index_by(&:box_name)
    end

    def dead_letter_classes
      @dead_letter_classes ||= config.dead_letter_classes.map(&:constantize)
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
  end
end
