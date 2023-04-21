# frozen_string_literal: true

class ImportOrder < Sbmt::Outbox::DryInteractor
  option :source

  def call(outbox_item, payload)
    Success()
  end
end
