# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :outbox_items do |t|
    t.uuid :uuid, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :outbox_items, :uuid, unique: true
  add_index :outbox_items, [:status, :bucket, :errors_count]
  add_index :outbox_items, [:event_key, :id]
  add_index :outbox_items, :created_at

  create_table :combined_outbox_items do |t|
    t.uuid :uuid, null: false
    t.string :event_name, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :combined_outbox_items, :uuid, unique: true
  add_index :combined_outbox_items, [:status, :bucket, :errors_count], name: "index_combined_outbox_items_on_status_and_bucket_and_err"
  add_index :combined_outbox_items, [:event_name, :event_key, :id]
  add_index :combined_outbox_items, :created_at

  create_table :inbox_items do |t|
    t.uuid :uuid, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :inbox_items, :uuid, unique: true
  add_index :inbox_items, [:status, :bucket, :errors_count]
  add_index :inbox_items, [:event_key, :id]
  add_index :inbox_items, :created_at
end
