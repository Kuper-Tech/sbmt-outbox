# frozen_string_literal: true

class PayloadRenderer < Sbmt::Outbox::DryInteractor
  param :outbox_item

  def call
    Success("custom-payload")
  end
end
