# frozen_string_literal: true

module Sbmt
  module Outbox
    module RetryStrategies
      class Base < Outbox::DryInteractor
        param :item

        def call
          raise NotImplementedError, "Implement #call for Sbmt::Outbox::RetryStrategies::Base"
        end
      end
    end
  end
end
