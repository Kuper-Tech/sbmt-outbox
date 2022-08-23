# frozen_string_literal: true

class RetryStrategy < Sbmt::Outbox::DryInteractor
  param :outbox_item

  def call
    true
  end
end
