# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Initializer
        OUTBOX_INITIALIZER_PATH = "config/initializers/outbox.rb"

        private

        def add_item_to_initializer(attr_name)
          template_data_with_push = <<~RUBY
            "#{namespaced_item_class_name}",
          RUBY

          template_data_with_append = <<~RUBY
            #{attr_name} << "#{namespaced_item_class_name}"
          RUBY

          initial_template_data = <<~RUBY
            #{attr_name}.push(
              "#{namespaced_item_class_name}"
            )

          RUBY

          content = File.binread(OUTBOX_INITIALIZER_PATH)
          data, after = if content.match?(/^\s*#{attr_name}\.push/)
            [optimize_indentation(template_data_with_push, 4), /^\s*#{attr_name}\.push\(\n/]
          elsif content.match?(/^\s*#{attr_name}\s+<</)
            [optimize_indentation(template_data_with_append, 2), /^\s*#{attr_name}\s+<< ".+?\n/]
          else
            # there is no config for items, so set it up initially
            [optimize_indentation(initial_template_data, 2), /^Rails.application.config.outbox.tap do.+?\n/]
          end
          inject_into_file OUTBOX_INITIALIZER_PATH, data, after: after
        end
      end
    end
  end
end
