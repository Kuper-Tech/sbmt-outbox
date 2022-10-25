# frozen_string_literal: true

module Sbmt
  module Outbox
    # Classes are the same now, but they may differ,
    # hence we should have separate API entrypoints
    class CreateInboxItem < Sbmt::Outbox::BaseCreateItem
    end
  end
end
