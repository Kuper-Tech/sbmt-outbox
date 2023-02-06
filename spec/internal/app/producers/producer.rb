# frozen_string_literal: true

class Producer < Sbmt::Outbox::DryInteractor
  param :topic

  def call(item, payload)
    publish
  end

  def publish
    true
  end
end
