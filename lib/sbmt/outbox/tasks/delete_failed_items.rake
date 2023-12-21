# frozen_string_literal: true

namespace :outbox do
  desc "Delete messages that we were unable to deliver"
  # rake 'outbox:delete_failed_items[some/box_item]'
  # rake 'outbox:delete_failed_items[some/box_item,1,2,3,4,5]'
  task :delete_failed_items, %i[] => :environment do |_, args|
    item_class_name, *ids = args.extras
    item_class_name = item_class_name.classify
    raise "Invalid item name" unless Sbmt::Outbox.item_classes.map(&:to_s).include?(item_class_name)
    item_class = item_class_name.constantize

    scope = item_class.failed
    scope = scope.where(id: ids) unless ids.empty?
    scope.in_batches.delete_all
  end
end
