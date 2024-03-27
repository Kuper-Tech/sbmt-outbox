# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class NoDelay < Base
        def call
          Success()
        end
      end
    end
  end
end
