# frozen_string_literal: true

module Sbmt
  module Outbox
    module PartitionStrategies
      class HashPartitioning < Outbox::DryInteractor
        param :key
        param :bucket_size

        def call
          Success(
            key.to_s.hash % bucket_size
          )
        end
      end
    end
  end
end
