# frozen_string_literal: true

namespace :outbox do
  desc "Update status of outbox/inbox items"
  task :update_status_items, [:klass_name, :status, :new_status, :start_time, :end_time, :batch_size, :sleep_time] => :environment do |_, args|
    args.with_defaults(start_time: nil, end_time: 6.hours.ago, batch_size: 1000, sleep_time: 0.5)

    klass_name = args[:klass_name]
    status = args[:status]
    new_status = args[:new_status]
    start_time = args[:start_time]
    end_time = args[:end_time]
    batch_size = args[:batch_size]
    sleep_time = args[:sleep_time]

    unless klass_name && status && new_status
      raise "Error: Class, current status, and new status must be specified. Example: rake outbox:update_status_items[OutboxItem,0,3]"
    end

    klass_name = klass_name.constantize
    query = klass_name.where(status: status)

    if start_time && end_time
      query = query.where(created_at: start_time..end_time)
    elsif start_time
      query = query.where(created_at: start_time..)
    elsif end_time
      query = query.where(created_at: ..end_time)
    end

    total_updated = 0
    query.in_batches(of: batch_size) do |batch|
      updated_count = batch.update_all(status: new_status)

      Rails.logger.info("Batch items updated: #{updated_count}")

      total_updated += updated_count
      sleep sleep_time
    end

    Rails.logger.info("Total items updated: #{total_updated}")
  end
end
