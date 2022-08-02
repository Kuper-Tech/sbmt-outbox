# frozen_string_literal: true

require "rails/engine"

module Sbmt
  module Outbox
    class Engine < Rails::Engine
      isolate_namespace Sbmt::Outbox

      config.outbox = ActiveSupport::OrderedOptions.new.tap do |c|
        c.error_tracker = "Sbmt::Outbox::ErrorTracker"
        c.item_classes = []
        c.paths = []
      end

      rake_tasks do
        load "sbmt/outbox/tasks/delete_failed_outbox_items.rake"
      end
    end
  end
end
