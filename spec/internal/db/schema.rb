# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :outbox_items do |t|
    t.string :uuid, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :outbox_items, :uuid, unique: true
  add_index :outbox_items, [:status, :bucket]
  add_index :outbox_items, :event_key
  add_index :outbox_items, :created_at

  create_table :combined_outbox_items do |t|
    t.string :uuid, null: false
    t.string :event_name, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :combined_outbox_items, :uuid, unique: true
  add_index :combined_outbox_items, [:status, :bucket]
  add_index :combined_outbox_items, [:event_name, :event_key]
  add_index :combined_outbox_items, :created_at

  create_table :inbox_items do |t|
    t.string :uuid, null: false
    t.bigint :event_key, null: false
    t.bigint :bucket, null: false
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :inbox_items, :uuid, unique: true
  add_index :inbox_items, [:status, :bucket]
  add_index :inbox_items, :event_key
  add_index :inbox_items, :created_at
end
