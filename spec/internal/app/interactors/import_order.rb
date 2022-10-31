# frozen_string_literal: true

class ImportOrder < Sbmt::Outbox::DryInteractor
  param :outbox_item
  param :payload

  def call
    Success()
  end
end
