# frozen_string_literal: true

# Engine root is used by rails_configuration to correctly
# load fixtures and support files
require "pathname"
ENGINE_ROOT = Pathname.new(File.expand_path("..", __dir__))

ENV["RAILS_ENV"] = "test"

require "combustion"

begin
  Combustion.initialize! :active_record, :active_job, :action_controller do
    if ENV["LOG"].to_s.empty?
      config.logger = ActiveSupport::TaggedLogging.new(Logger.new(nil))
      config.log_level = :fatal
    else
      config.logger = ActiveSupport::TaggedLogging.new(Logger.new($stdout))
      config.log_level = :debug
    end

    config.active_record.logger = config.logger

    config.i18n.available_locales = [:ru, :en]
    config.i18n.default_locale = :ru
    config.active_job.queue_adapter = :test
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

Rails.application.load_tasks

ActiveRecord::Base.logger = Rails.logger

require "rspec/rails"
# Add additional requires below this line. Rails is not loaded until this point!
require "factory_bot"
require "yabeda/rspec"

RSpec::Matchers.define_negated_matcher :not_increment_yabeda_counter, :increment_yabeda_counter
RSpec::Matchers.define_negated_matcher :not_update_yabeda_gauge, :update_yabeda_gauge

require "sbmt/outbox/instrumentation/open_telemetry_loader"

Dir[Sbmt::Outbox::Engine.root.join("spec/support/**/*.rb")].sort.each { |f| require f }
Dir[Sbmt::Outbox::Engine.root.join("spec/factories/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  config.fixture_path = Rails.root.join("spec/fixtures").to_s
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  redis = RedisClient.new(url: ENV["REDIS_URL"])
  config.before do
    redis.call("FLUSHDB")
    Sbmt::Outbox.memory_store.clear
  end
end
