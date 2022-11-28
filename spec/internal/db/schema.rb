# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :outbox_items do |t|
    t.string :uuid, null: false
    t.string :event_name, null: false
    t.bigint :event_key, null: false
    t.bigint :partition_key, null: false, default: 1
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :outbox_items, :uuid, unique: true
  add_index :outbox_items, :status
  add_index :outbox_items, [:event_name, :event_key]

  create_table :inbox_items do |t|
    t.string :uuid, null: false
    t.string :event_name, null: false
    t.bigint :event_key, null: false
    t.bigint :partition_key, null: false, default: 1
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.text :error_log
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :inbox_items, :uuid, unique: true
  add_index :inbox_items, :status
  add_index :inbox_items, [:event_name, :event_key]
end
