# frozen_string_literal: true

class Producer < Sbmt::Outbox::DryInteractor
  option :topic
  option :kafka, optional: true

  def call(item, payload)
    publish
  end

  def publish
    true
  end
end
