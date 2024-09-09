# frozen_string_literal: true

if ActiveRecord.version >= Gem::Version.new("7.0.0")
  Rails.application.config.active_record.tap do |config|
    config.query_log_tags << {
      box_name: ->(context) { context[:box_item]&.class&.box_name },
      box_item_id: ->(context) { context[:box_item]&.uuid }
    }
  end
end
