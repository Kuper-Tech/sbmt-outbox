# frozen_string_literal: true

require "digest/sha1"

module Sbmt
  module Outbox
    module PartitionStrategies
      class HashPartitioning < Outbox::DryInteractor
        param :key
        param :bucket_size

        def call
          Success(
            Digest::SHA1.hexdigest(key.to_s).to_i(16) % bucket_size
          )
        end
      end
    end
  end
end
