# frozen_string_literal: true

namespace :outbox do
  desc "Retry messages that we were unable to deliver"
  # rake 'outbox:process_outbox_items[Retail::Onboarding::OutboxItem,1,2,3,4,5]'
  task :process_outbox_items, %i[] => :environment do |_, args|
    item_class_name, *ids = args.extras
    raise "Invalid item name" unless Sbmt::Outbox.outbox_item_classes.map(&:to_s).include?(item_class_name)
    item_class = item_class_name.constantize

    scope = item_class.for_processing.select(:id)
    scope = scope.where(id: ids) unless ids.empty?
    scope.find_each do |item|
      Sbmt::Outbox::ProcessItem.call(item_class, item.id)
    end
  end
end
