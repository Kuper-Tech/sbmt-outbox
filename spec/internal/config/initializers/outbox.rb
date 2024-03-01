# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  config.poller.tap do |pc|
    pc.tactic = "noop"
    pc.queue_delay = 0.1
  end

  config.processor.tap do |pc|
    pc.brpop_delay = 0.1
  end

  config.worker.tap do |wc|
    wc.rate_limit = 1000
    wc.rate_interval = 10
    wc.shuffle_jobs = false
  end
end
