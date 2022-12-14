# frozen_string_literal: true

module Sbmt
  module Outbox
    module Middleware
      class Runner
        attr_reader :stack

        def initialize(stack)
          @stack = stack
        end

        def call(*args)
          return yield if stack.empty?

          chain = stack.map { |i| i.new }
          traverse_chain = proc do
            if chain.empty?
              yield
            else
              chain.shift.call(*args, &traverse_chain)
            end
          end
          traverse_chain.call
        end
      end
    end
  end
end
