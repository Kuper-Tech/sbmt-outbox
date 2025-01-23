# frozen_string_literal: true

namespace :outbox do
  desc "Delete outbox/inbox items"
  task :delete_items, [:klass_name, :status, :start_time, :end_time, :batch_size, :sleep_time] => :environment do |_, args|
    args.with_defaults(start_time: nil, end_time: 6.hours.ago, batch_size: 1000, sleep_time: 0.5)

    klass_name = args[:klass_name]
    status = args[:status]
    start_time = args[:start_time]
    end_time = args[:end_time]
    batch_size = args[:batch_size]
    sleep_time = args[:sleep_time]

    unless klass_name && status
      raise "Error: Class and status must be specified. Example: rake outbox:delete_items[OutboxItem,1]"
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

    total_deleted = 0
    query.in_batches(of: batch_size) do |batch|
      deleted_count = batch.delete_all

      Rails.logger.info("Batch items deleted: #{deleted_count}")

      total_deleted += deleted_count

      sleep sleep_time
    end

    Rails.logger.info("Total items deleted: #{total_deleted}")
  end
end
