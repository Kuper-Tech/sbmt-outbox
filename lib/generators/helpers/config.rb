# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Config
        OUTBOX_CONFIG_PATH = "config/outbox.yml"

        private

        def config_exists?
          File.exist?(OUTBOX_CONFIG_PATH)
        end

        def create_config_with_template(template_name)
          template template_name, File.join(OUTBOX_CONFIG_PATH)
        end

        def add_inbox_item_to_config(item_path)
          item_template_data = <<~RUBY
            #{item_path}:
              partition_size: 1
              partition_strategy: hash
              retention: P1W
              max_retries: 7
              retry_strategies:
                - exponential_backoff
            #  see README to learn more about transport configuration
            #  transports: {}
          RUBY

          add_item_to_config("inbox_items", item_template_data)
        end

        def add_outbox_item_to_config(item_path)
          item_template_data = <<~RUBY
            #{item_path}:
              partition_size: 1
              partition_strategy: number
              retention: P3D
              max_retries: 7
              retry_strategies:
                - exponential_backoff
            #  see README to learn more about transport configuration
            #  transports: {}
          RUBY

          add_item_to_config("outbox_items", item_template_data)
        end

        def add_item_to_config(config_block_name, item_template_data)
          template_data_with_parent = <<~RUBY
            #{config_block_name}:
            #{optimize_indentation(item_template_data, 2)}
          RUBY

          if File.binread(OUTBOX_CONFIG_PATH).match?(/^\s*#{config_block_name}:/)
            # if config already contains non-empty/non-commented-out inbox_items/outbox_items block
            inject_into_file OUTBOX_CONFIG_PATH, optimize_indentation(item_template_data, 4), after: /^\s*#{config_block_name}:\s*\n/
          else
            # there is no config for our items
            # so we just set it up initially
            inject_into_file OUTBOX_CONFIG_PATH, optimize_indentation(template_data_with_parent, 2), after: /^default:.+?\n/
          end
        end
      end
    end
  end
end
