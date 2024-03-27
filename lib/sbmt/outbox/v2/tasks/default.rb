# frozen_string_literal: true

require "sbmt/outbox/v2/tasks/base"

module Sbmt
  module Outbox
    module V2
      module Tasks
        class Default < Base
          def to_s
            "#{item_class.box_type}/#{item_class.box_name}"
          end
        end
      end
    end
  end
end
