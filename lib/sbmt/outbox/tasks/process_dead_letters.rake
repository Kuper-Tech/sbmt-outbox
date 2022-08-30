# frozen_string_literal: true

namespace :outbox do
  desc "Process messages that we were unable to consume"
  # rake 'inbox:process_dead_letters[Some::DeadLetterModel,1,2,3,4,5]'
  task :process_dead_letters, %i[] => :environment do |_, args|
    class_name, *ids = args.extras
    raise "Invalid item name" unless Sbmt::Outbox.dead_letter_classes.map(&:to_s).include?(class_name)
    dead_letter_class = class_name.constantize

    scope = dead_letter_class.all
    scope = scope.where(id: ids) if args.extras.present?
    scope.find_each do |dead_letter|
      Sbmt::Outbox::ProcessDeadLetter.call(dead_letter.class, dead_letter.id)
    end
  end
end
