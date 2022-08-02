# frozen_string_literal: true

class HttpOrderSender < Sbmt::Outbox::DryInteractor
  param :outbox_item
  param :payload

  def call
    Success()
  end
end
