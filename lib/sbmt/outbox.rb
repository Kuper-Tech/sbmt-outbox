# frozen_string_literal: true

require "ruby2_keywords"
require "rails"
require "sidekiq"
require "sidekiq-unique-jobs"
require "dry-initializer"
require "dry-monads"
require "dry/monads/do"
require "schked"
require "waterdrop"
require "yabeda"

require_relative "outbox/version"
require_relative "outbox/error_tracker"
require_relative "outbox/engine"

module Sbmt
  module Outbox
    module_function

    def config
      @config ||= Rails.application.config.outbox
    end

    def error_tracker
      @error_tracker ||= config.error_tracker.constantize
    end

    def item_classes
      @item_classes ||= config.item_classes.map(&:constantize)
    end

    def yaml_config
      @yaml_config ||= config.paths.each_with_object({}.with_indifferent_access) do |path, memo|
        memo.deep_merge!(
          YAML.safe_load(ERB.new(File.read(path)).result, [], [], true)
            .with_indifferent_access
            .fetch(Rails.env, {})
        )
      end
    end
  end
end
