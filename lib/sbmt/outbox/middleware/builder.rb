# frozen_string_literal: true

module Sbmt
  module Outbox
    module Middleware
      class Builder
        def initialize(middlewares)
          middlewares.each { |middleware| stack << middleware }
        end

        def call(...)
          Runner.new(stack.dup).call(...)
        end

        private

        def stack
          @stack ||= []
        end
      end
    end
  end
end
