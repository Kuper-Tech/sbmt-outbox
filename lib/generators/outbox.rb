# frozen_string_literal: true

require "rails/generators/named_base"
require_relative "helpers"

module Outbox
  module Generators
    class Base < Rails::Generators::Base
      include Helpers::Alerts
      include Helpers::Migration
      include Helpers::Initializer
      include Helpers::Config
      include Helpers::Values
      include Helpers::Paas
      include Helpers::Outboxfile
    end

    class NamedBase < Rails::Generators::NamedBase
      include Helpers::Alerts
      include Helpers::Migration
      include Helpers::Initializer
      include Helpers::Config
      include Helpers::Values
      include Helpers::Paas
      include Helpers::Outboxfile
    end
  end
end
