# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  config.poller.tap do |pc|
    pc.tactic = "noop"
    pc.queue_delay = 0
    pc.min_queue_size = 1
  end

  config.processor.tap do |pc|
    pc.brpop_delay = 0.1
  end
end
