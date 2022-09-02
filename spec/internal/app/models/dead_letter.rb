# frozen_string_literal: true

class DeadLetter < Sbmt::Outbox::DeadLetter
  include Dry::Monads[:result]

  def handler
    ->(payload, metadata) { Success() }
  end

  def payload
    proto_payload
  end
end
