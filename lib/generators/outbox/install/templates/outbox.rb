# frozen_string_literal: true

Rails.application.config.outbox.tap do |config|
  # setup custom ErrorTracker
  # config.error_tracker = "ErrorTracker"

  # customize redis
  # config.redis = {url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379")}

  # setup custom batch process middlewares
  # config.batch_process_middlewares << "MyBatchProcessMiddleware"

  # setup custom item process middlewares
  # config.item_process_middlewares << "MyItemProcessMiddleware"

  # config.process_items.tap do |x|
  #   # maximum processing time of the batch, after which the batch will be considered hung and processing will be aborted
  #   x[:general_timeout] = 180
  #   # maximum patch processing time, after which the processing of the patch will be aborted in the current thread,
  #   # and the next thread that picks up the batch will start processing from the same place
  #   x[:cutoff_timeout] = 60
  #   # batch size
  #   x[:batch_size] = 200
  # end

  # config.worker.tap do |worker|
  #   # number of batches that one thread will process per rate interval
  #   worker[:rate_limit] = 10
  #   # rate interval in seconds
  #   worker[:rate_interval] = 60
  # end
end
