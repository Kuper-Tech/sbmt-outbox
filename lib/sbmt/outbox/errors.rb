# frozen_string_literal: true

module Sbmt
  module Outbox
    class Error < StandardError
    end

    class ConfigError < Error
    end

    class DatabaseError < Error
    end

    DB_CONNECTION_ERRORS = [
      ActiveRecord::StatementInvalid,
      ActiveRecord::ConnectionNotEstablished,
      DatabaseError
    ].freeze
  end
end
