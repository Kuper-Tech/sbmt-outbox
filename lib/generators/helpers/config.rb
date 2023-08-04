# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Config
        CONFIG_PATH = "config/outbox.yml"

        private

        def config_exists?
          File.exist?(CONFIG_PATH)
        end

        def check_config!
          return if config_exists?

          if yes?("Seems like `config/outbox.yml` doesn't exist. Would you like to generate it?")
            generate "outbox:install"
          else
            raise Rails::Generators::Error, "Something went wrong: `config/outbox.yml` is missing. " \
                                        "Please generate one by running `bin/rails g outbox:install` " \
                                        "or add it manually."
          end
        end

        def add_item_to_config(config_block_name, item_template_data)
          template_data_with_parent = <<~RUBY
            #{config_block_name}:
            #{optimize_indentation(item_template_data, 2)}
          RUBY

          data, after = if File.binread(CONFIG_PATH).match?(/^\s*#{config_block_name}:/)
            # if config already contains non-empty/non-commented-out inbox_items/outbox_items block
            [optimize_indentation(item_template_data, 4), /^\s*#{config_block_name}:\s*\n/]
          else
            # there is no config for our items
            # so we just set it up initially
            [optimize_indentation(template_data_with_parent, 2), /^default:.+?\n/]
          end
          inject_into_file CONFIG_PATH, data, after: after
        end
      end
    end
  end
end
