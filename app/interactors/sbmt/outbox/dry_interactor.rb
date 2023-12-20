# frozen_string_literal: true

module Sbmt
  module Outbox
    class DryInteractor
      extend Dry::Initializer
      include Dry::Monads[:result, :do, :maybe, :list, :try]
      include AfterCommitEverywhere

      class << self
        def call(*args, **kwargs)
          new(*args, **kwargs).call
        end
      end
    end
  end
end
