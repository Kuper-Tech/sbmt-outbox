# frozen_string_literal: true

module Sbmt
  module Outbox
    class DatabaseSwitcher
      def self.use_slave
        yield
      end

      def self.use_master
        yield
      end
    end
  end
end
