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

      def check_installed
        if config_exists?
          return if no?("outbox.yml already exists, continue?")
        end

        create_outboxfile
        create_initializer
        create_config
        patch_alerts
      end

      private

      def create_outboxfile
        return if options[:skip_outboxfile]

        create_outboxfile_with_template("Outboxfile")
      end

      def create_initializer
        return if options[:skip_initializer]

        create_initializer_with_template("outbox.rb")
      end

      def create_config
        return if options[:skip_config]

        create_config_with_template("outbox.yml")
      end

      def patch_alerts
        return unless paas_app?
        return if options[:skip_alerts]

        patch_alerts_with_template_data
      end
    end
  end
end
