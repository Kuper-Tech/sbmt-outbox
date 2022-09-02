# frozen_string_literal: true

module Sbmt
  module Outbox
    class Error < StandardError
    end

    class ProcessItemError < Error
    end

    class ProcessDeadLetterError < Error
    end
  end
end
