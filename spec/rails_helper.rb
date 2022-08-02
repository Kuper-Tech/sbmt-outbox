# frozen_string_literal: true

# Engine root is used by rails_configuration to correctly
# load fixtures and support files
require "pathname"
ENGINE_ROOT = Pathname.new(File.expand_path("..", __dir__))

ENV["RAILS_ENV"] = "test"

require "combustion"

begin
  Combustion.initialize! :active_record do
    config.logger = Logger.new(nil)
    config.log_level = :fatal
    config.i18n.available_locales = [:ru, :en]
    config.i18n.default_locale = :ru
  end
rescue => e
  # Fail fast if application couldn't be loaded
  if e.message.include?("Unknown database")
    warn "💥 Database must be reseted by passing env variable `DB_RESET=1`"
  else
    warn "💥 Failed to load the app: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  exit(1)
end

require "rspec/rails"
# Add additional requires below this line. Rails is not loaded until this point!
require "fabrication"
require "sidekiq/testing"

Dir[Sbmt::Outbox::Engine.root.join("spec/support/**/*.rb")].sort.each { |f| require f }
Dir[Sbmt::Outbox::Engine.root.join("spec/fabricators/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers

  config.fixture_path = "#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before do
    Sidekiq::Queues.clear_all
  end
end
