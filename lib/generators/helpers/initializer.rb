# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Initializer
        OUTBOX_INITIALIZER_PATH = "config/initializers/outbox.rb"

        private

        def create_initializer_with_template(template_name)
          template template_name, File.join(OUTBOX_INITIALIZER_PATH)
        end

        def add_inbox_item_to_initializer(namespaced_class_name)
          add_item_to_initializer("config.inbox_item_classes", namespaced_class_name)
        end

        def add_outbox_item_to_initializer(namespaced_class_name)
          add_item_to_initializer("config.outbox_item_classes", namespaced_class_name)
        end

        def add_item_to_initializer(attr_name, namespaced_class_name)
          template_data_with_push = <<~RUBY
            "#{namespaced_class_name}",
          RUBY

          template_data_with_append = <<~RUBY
            #{attr_name} << "#{namespaced_class_name}"
          RUBY

          initial_template_data = <<~RUBY
            #{attr_name}.push(
              "#{namespaced_class_name}"
            )

          RUBY

          content = File.binread(OUTBOX_INITIALIZER_PATH)
          if content.match?(/^\s*#{attr_name}\.push/)
            inject_into_file OUTBOX_INITIALIZER_PATH, optimize_indentation(template_data_with_push, 4), after: /^\s*#{attr_name}\.push\(\n/
          elsif content.match?(/^\s*#{attr_name}\s+<</)
            inject_into_file OUTBOX_INITIALIZER_PATH, optimize_indentation(template_data_with_append, 2), after: /^\s*#{attr_name}\s+<< ".+?\n/
          else
            # there is no config for items, so set it up initially
            inject_into_file OUTBOX_INITIALIZER_PATH, optimize_indentation(initial_template_data, 2), after: /^Rails.application.config.outbox.tap do.+?\n/
          end
        end
      end
    end
  end
end
