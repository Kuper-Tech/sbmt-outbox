# frozen_string_literal: true

module Sbmt
  module Outbox
    module Metrics
      module Utils
        extend self

        def metric_safe(str)
          str.tr("/", "-")
        end
      end
    end
  end
end
