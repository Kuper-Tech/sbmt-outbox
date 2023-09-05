# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  # setup custom ErrorTracker
  # config.error_tracker = "ErrorTracker"

  # customize redis
  # config.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}

  # default config paths
  config.paths << Rails.root.join("config/outbox.yml").to_s

  # setup inbox item classes
  # config.inbox_item_classes << "MyInboxItem"

  # setup outbox item classes
  # config.outbox_item_classes << "MyOutboxItem"

  # setup custom batch process middlewares
  # config.batch_process_middlewares << "MyBatchProcessMiddleware"

  # setup custom item process middlewares
  # config.item_process_middlewares << "MyItemProcessMiddleware"

  # setup timeouts
  config.process_items.tap do |x|
    x[:general_timeout] = 180 # максимальное время обработки батча, после которого батч будет считаться зависшим и обработка будет прервана
    x[:cutoff_timeout] = 60 # максимально время обработки батча, после которого обработка батча будет прервана в текущем потоке, а следующий подхвативший поток начнет обработку батча с того же места
    x[:batch_size] = 200 # размер батча
  end

  # setup limits
  config.worker.tap do |worker|
    worker[:rate_limit] = 10 # количество батчей, которое один поток обработает за rate_interval
    worker[:rate_interval] = 60 # секунды
  end
end
