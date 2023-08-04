# frozen_string_literal: true

require "generators/outbox"

module Outbox
  module Generators
    class TransportGenerator < NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :transport, required: true, type: :string, banner: "sbmt/kafka_producer"

      class_option :kind, type: :string, desc: "Either inbox or outbox", banner: "inbox/outbox", required: true
      class_option :topic, type: :string, banner: "my-topic-name"
      class_option :source, type: :string, banner: "kafka"
      class_option :target, type: :string, banner: "order"
      class_option :event_name, type: :string, default: "", banner: "order_created"

      def check_name!
        return if options[:kind].in?(%w[inbox outbox])

        raise Rails::Generators::Error, "Unknown transport type. Should be inbox or outbox"
      end

      def check!
        check_config!
      end

      def check_item_exists!
        return if item_exists?

        raise Rails::Generators::Error, "Item `#{item_name}` does not exist in the `#{options[:kind]}_items` " \
                                        "section of #{CONFIG_PATH}. You may insert this item by running " \
                                        "`bin/rails g outbox:item #{item_name} --kind #{options[:kind]}`"
      end

      def insert_transport
        data = optimize_indentation(template, 6)
        insert_into_file CONFIG_PATH, data, after: "#{item_name.underscore}:\n", force: true
      end

      private

      def item_name
        name
      end

      def item_exists?
        File.binread(CONFIG_PATH).match?(%r{#{options[:kind]}_items:.*#{item_name.underscore}:}m)
      end

      def template_path
        File.join(TransportGenerator.source_root, "#{options[:kind]}_transport.yml.erb")
      end

      def template
        ERB.new(File.read(template_path), trim_mode: "%-").result(binding)
      end
    end
  end
end
