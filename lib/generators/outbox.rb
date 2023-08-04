# frozen_string_literal: true

require "rails/generators"
require_relative "helpers"

module Outbox
  module Generators
    class Base < Rails::Generators::Base
      include Helpers::Alerts
      include Helpers::Config
      include Helpers::Initializer
      include Helpers::Paas
    end

    class NamedBase < Rails::Generators::NamedBase
      include Helpers::Config
      include Helpers::Initializer
      include Helpers::Items
      include Helpers::Migration
      include Helpers::Paas
      include Helpers::Values
    end
  end
end
