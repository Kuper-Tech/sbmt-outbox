# frozen_string_literal: true

module Outbox
  module Generators
    module Helpers
      module Items
        def namespaced_item_class_name
          file_path.camelize
        end

        def item_path
          file_path
        end
      end
    end
  end
end
