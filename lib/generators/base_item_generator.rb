# frozen_string_literal: true

require_relative "outbox"

module Outbox
  module Generators
    class BaseItemGenerator < NamedBase
      class_option :skip_migration, type: :boolean, default: false, desc: "Skip creating migration"
      class_option :skip_model, type: :boolean, default: false, desc: "Skip creating model class"
      class_option :skip_initializer, type: :boolean, default: false, desc: "Skip modifying config/initializers/outbox.rb"
      class_option :skip_config, type: :boolean, default: false, desc: "Skip modifying config/outbox.yml"
      class_option :skip_values, type: :boolean, default: false, desc: "Skip modifying configs/values.yaml"

      def initial_setup
        return if config_exists?

        generate "outbox:install"
      end

      def create_migration
        return if options[:skip_migration]

        raise "Invalid item: #{namespaced_item_class_name}. Supported formats are: SomeModel::InboxItem or SomeModel::OutboxItem" unless inbox_item? || outbox_item?

        create_migration_file(migration_class_name, migration_table_name)
      end

      def create_model
        return if options[:skip_model]

        create_inbox_model_file(item_path) if inbox_item?
        create_outbox_model_file(item_path) if outbox_item?
      end

      def patch_initializer
        return if options[:skip_initializer]

        add_inbox_item_to_initializer(namespaced_item_class_name) if inbox_item?
        add_outbox_item_to_initializer(namespaced_item_class_name) if outbox_item?
      end

      def patch_config
        return if options[:skip_config]

        add_inbox_item_to_config(item_path) if inbox_item?
        add_outbox_item_to_config(item_path) if outbox_item?
      end

      def patch_values
        return unless paas_app?
        return if options[:skip_values]

        add_inbox_item_to_values(item_path) if inbox_item?
        add_outbox_item_to_values(item_path) if outbox_item?
      end

      private

      def kind
        raise NotImplementedError, "implement this in a subsclass, possible values are :inbox or :outbox"
      end

      def item_class_name
        file_name.camelize
      end

      def namespaced_item_class_name
        file_path.camelize
      end

      def item_path
        file_path
      end

      def inbox_item?
        kind == :inbox && item_class_name.match?(/InboxItem$/)
      end

      def outbox_item?
        kind == :outbox && item_class_name.match?(/OutboxItem$/)
      end
    end
  end
end
