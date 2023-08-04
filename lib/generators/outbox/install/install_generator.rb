# frozen_string_literal: true

require "generators/outbox"

module Outbox
  module Generators
    class InstallGenerator < Base
      source_root File.expand_path("templates", __dir__)

      class_option :skip_outboxfile, type: :boolean, default: false, desc: "Skip creating Outboxfile"
      class_option :skip_initializer, type: :boolean, default: false, desc: "Skip creating config/initializers/outbox.rb"
      class_option :skip_config, type: :boolean, default: false, desc: "Skip creating config/outbox.yml"
      class_option :skip_alerts, type: :boolean, default: false, desc: "Skip patching configs/alerts.yaml"

      def create_outboxfile
        return if options[:skip_outboxfile]

        copy_file "Outboxfile", "Outboxfile"
      end

      def create_initializer
        return if options[:skip_initializer]

        copy_file "outbox.rb", OUTBOX_INITIALIZER_PATH
      end

      def create_config
        return if options[:skip_config]

        copy_file "outbox.yml", CONFIG_PATH
      end

      def patch_alerts
        return if options[:skip_alerts]
        return unless paas_app?

        patch_alerts_with_template_data
      end
    end
  end
end
