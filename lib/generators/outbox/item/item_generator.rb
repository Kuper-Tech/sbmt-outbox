# frozen_string_literal: true

require "generators/outbox"

module Outbox
  module Generators
    class ItemGenerator < NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :kind, type: :string, desc: "Either inbox or outbox", banner: "inbox/outbox", required: true
      class_option :skip_migration, type: :boolean, default: false, desc: "Skip creating migration"
      class_option :skip_model, type: :boolean, default: false, desc: "Skip creating model class"
      class_option :skip_config, type: :boolean, default: false, desc: "Skip modifying config/outbox.yml"
      class_option :skip_values, type: :boolean, default: false, desc: "Skip modifying configs/values.yaml"

      def check_kind!
        return if options[:kind].in?(%w[inbox outbox])

        raise Rails::Generators::Error, "Unknown item kind. " \
                                        "Please specify `--kind inbox` or `--kind outbox`"
      end

      def check!
        check_config!
      end

      def validate_item_name
        return if file_name.underscore.match?(%r{#{options[:kind]}_item$})

        continue = yes?(
          "Warning: your item's name doesn't match the conventional" \
          " name format (i.e. Some#{options[:kind].camelize}Item). Continue?"
        )
        return if continue

        raise Rails::Generators::Error, "Aborting"
      end

      def create_migration
        return if options[:skip_migration]

        create_migration_file(migration_class_name, migration_table_name)
      end

      def create_model
        return if options[:skip_model]

        template "#{options[:kind]}_item.rb", File.join("app/models", "#{item_path}.rb")
      end

      def patch_config
        return if options[:skip_config]

        item_template_data = if options[:kind] == "inbox"
          <<~RUBY
            #{item_path}:
              partition_size: 1
              partition_strategy: hash
              retention: P1W
              max_retries: 7
              retry_strategies:
                - exponential_backoff
            #  # see README to learn more about transport configuration
            #  transports: {}
          RUBY
        else
          <<~RUBY
            #{item_path}:
              partition_size: 1
              partition_strategy: number
              retention: P3D
              max_retries: 7
              retry_strategies:
                - exponential_backoff
            #  # see README to learn more about transport configuration
            #  transports: {}
          RUBY
        end

        add_item_to_config("#{options[:kind]}_items", item_template_data)
      end

      def patch_values
        return if options[:skip_values]
        return unless paas_app?

        # e.g. order/inbox_item => inbox-order-inbox-items
        deployment_name = "#{options[:kind]}-" + dasherize_item(item_path)

        add_item_to_values(deployment_name.pluralize, item_path)
      end
    end
  end
end
