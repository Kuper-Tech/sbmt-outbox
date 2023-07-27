# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Migration
        private

        def create_migration_file(migration_class_name, migration_table_name)
          return false if find_existing_migration(migration_class_name.tableize)

          result = generate "rails:migration", migration_class_name, "--no-timestamps"
          return unless result

          migration_filepath = find_existing_migration(migration_class_name.tableize)
          return unless migration_filepath

          patch_migration_with_template_data(migration_filepath, migration_table_name)
        end

        def find_existing_migration(name)
          base_path = "db/migrate"
          found_files = Dir.glob("*_#{name}.rb", base: base_path)
          return if found_files.size != 1

          "#{base_path}/#{found_files[0]}"
        end

        def patch_migration_with_template_data(migration_filepath, table_name)
          data_to_replace = /^\s*create_table :#{table_name}.+?end\n/m

          template_data = <<~RUBY
            create_table :#{table_name} do |t|
              t.uuid :uuid, null: false
              t.string :event_key, null: false
              t.integer :bucket, null: false
              t.integer :status, null: false, default: 0
              t.jsonb :options
              t.binary :proto_payload, null: false
              t.integer :errors_count, null: false, default: 0
              t.text :error_log
              t.timestamp :processed_at
              t.timestamps null: false
            end
      
            add_index :#{table_name}, :uuid, unique: true
            add_index :#{table_name}, [:status, :bucket]
            add_index :#{table_name}, :event_key
            add_index :#{table_name}, :created_at
          RUBY

          gsub_file(migration_filepath, data_to_replace, optimize_indentation(template_data, 4))
        end

        def create_inbox_model_file(path)
          template "inbox_item.rb", File.join("app/models", "#{path}.rb")
        end

        def create_outbox_model_file(path)
          template "outbox_item.rb", File.join("app/models", "#{path}.rb")
        end

        def migration_class_name
          "Create" + namespaced_item_class_name.gsub("::", "").pluralize
        end

        def migration_table_name
          namespaced_item_class_name.tableize.tr("/", "_")
        end
      end
    end
  end
end
