# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  config.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}
end
