# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :outbox_items do |t|
    t.string :uuid, null: false
    t.string :event_name, null: false
    t.bigint :event_key, null: false
    t.json :options
    t.binary :proto_payload, null: false
    t.integer :status, null: false, default: 0
    t.integer :errors_count, null: false, default: 0
    t.timestamp :processed_at
    t.timestamps
  end

  add_index :outbox_items, :uuid, unique: true
  add_index :outbox_items, :status
  add_index :outbox_items, [:event_name, :event_key], where: "status = 2"

  create_table :dead_letters do |t|
    t.binary :proto_payload, null: false
    t.json :metadata
    t.string :topic_name, null: false
    t.text :error
    t.timestamps
  end
end
