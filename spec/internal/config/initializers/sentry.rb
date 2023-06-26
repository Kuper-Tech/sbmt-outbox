# frozen_string_literal: true

SENTRY_DUMMY_DSN = "http://12345:67890@sentry.localdomain/sentry/42"
Sentry.init do |config|
  config.dsn = SENTRY_DUMMY_DSN
  config.transport.transport_class = Sentry::DummyTransport
  config.enabled_environments = %w[Rails.env]
  config.traces_sample_rate = 0.5
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
end
