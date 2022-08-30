# frozen_string_literal: true

module Sbmt
  module Outbox
    class Error < StandardError
    end

    class ProcessItemError < Error
    end
  end
end
