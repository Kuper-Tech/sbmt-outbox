# frozen_string_literal: true

require "generators/base_item_generator"

module Outbox
  module Generators
    class OutboxItemGenerator < BaseItemGenerator
      source_root File.expand_path("templates", __dir__)

      def kind
        :outbox
      end
    end
  end
end
