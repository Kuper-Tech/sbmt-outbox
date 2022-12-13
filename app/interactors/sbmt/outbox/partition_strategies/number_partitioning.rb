# frozen_string_literal: true

module Sbmt
  module Outbox
    module PartitionStrategies
      class NumberPartitioning < Outbox::DryInteractor
        param :key
        param :bucket_size

        def call
          parsed_key =
            case key
            when Integer
              key
            else
              key.delete("^0-9").to_i
            end

          Success(
            parsed_key % bucket_size
          )
        end
      end
    end
  end
end
