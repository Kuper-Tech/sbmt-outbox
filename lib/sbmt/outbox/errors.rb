# frozen_string_literal: true

module Sbmt
  module Outbox
    class Error < StandardError
    end

    class ConfigError < Error
    end
  end
end
