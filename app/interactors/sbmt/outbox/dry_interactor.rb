# frozen_string_literal: true

module Sbmt
  module Outbox
    class DryInteractor
      extend Dry::Initializer
      include Dry::Monads[:result, :do, :maybe, :list]

      class << self
        ruby2_keywords def call(*params)
          new(*params).call
        end
      end
    end
  end
end
