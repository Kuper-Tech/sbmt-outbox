# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] - yyyy-mm-dd

## [6.0.0] - 2024-02-04

### Added
- support of worker v2 architecture, which simplifies outbox configuration (no manual selection of partitions / concurrency anymore)
- worker v2: worker process is now consists of two parts: poller + processor
- worker v2: each worker process contains X (1 by default) poll-thread and Y (4 by default) process-threads
- worker v2: poller is responsible for async polling database (usually RO-replicas) changes, i.e. inbox/outbox items ready for processing
- worker v2: processor is responsible for transactional processing of inbox/outbox items
- worker v2: poller / processor communicate via redis job queue per inbox/outbox item
- worker v2: poller / processor consistency is backed by redis locks per box/bucket
- worker v2: more poller / processor metrics to simplify process scaling (i.e. HPA)
- worker v2: poller's poll tactics for different performance profiles: default, aggressive, low-priority

## [5.0.4] - 18-03-2024

### Added

- Add global config option `disposable_transports`, and set to `false` by default.

## [5.0.3] - 14-03-2024

### Changed

- A transport might be invoked as a disposable object.

## [5.0.1] - 2024-02-29

### Fixed

- fixed backward compatibility with proto_payload

## [5.0.0] - 2024-02-27

### Added

- track errors when the worker get a failure

### Changed

- dropped support of Ruby 2.5 and 2.6
- removed Sbmt::Outbox::Item
- removed after_commit_everywhere
- removed `redis_servers=` config option. Configure Redis with `redis=` config option
- changed the expected result of a transport while processing to only False result is consedered as failed
- make ErrorTracker to send errors to Sentry (if available)
- re-plugged Schked as an optional dependency
- replaced Sidekiq with ActiveJob. Don't forget to set `config.active_job.queue_adapter = :sidekiq`
- accept box names as arguments in maintenance tasks, ex: `rake outbox:retry_failed_items[some/box_item]`
- rename proto_payload to payload
- replaced gem fabrication with factory_bot_rails
- now item_process_middlewares is only called if `Sbmt::Outbox::Item` is actually being processed
- changed item_process_middlewares call signature: `item` is passed to `#call` method instead of `item_id`, `job` and `options` parameter are removed

### Fixed

- don't include buckets into a partition lock key

## [4.11.2] - 15-12-2023

### Added

### Changed

### Fixed
- optimized removing of obsolete items by using an index on the `created_at` field

## [4.11.1] - 12-12-2023

### Added

### Changed

### Fixed

- the size of the redis connection pool is now equal to the number of threads, which will avoid issues with connection blocking.

## [4.11.0] - 17-11-2023

### Added

- added a comment to the migration generator for the proto_payload column if a MySQL database is used

### Changed

- changed a base class for the BaseItem to ApplicationRecord

## [4.10.1] - 17-10-2023

### Fixed

- add backtrace limit

## [4.10.0] - 12-10-2023

### Changed

- reduced the number of logs for the column `error_log`

## [4.9.0] - 22-09-2023

### Added

- plug opentelemetry tracing

## [4.8.8] - 25-09-2023

### Fixed

- don't cache DB errors in the item processor

## [4.8.7] - 22-09-2023

### Fixed

- deep symbolize config keys when initializing a Redis client

## [4.8.6] - 21-09-2023

### Fixed

- fix working with connection errors. The previous approach leads to hanging of the thread. Now, it uses `Rails.application.executor.wrap` mechanism.

## [4.8.5] - 20-09-2023

### Fixed

- symbolize config keys when initializing a Redis client

## [4.8.4] - 20-09-2023

### Fixed

- get correct lock when deleting old items

## [4.8.3] - 14-09-2023

### Fixed

- handle and return database errors while processing an item, and then try to recover 3 times

## [4.8.2] - 13-09-2023

### Fixed

- use correct redis client in delete stale items job

## [4.8.1] - 13-09-2023

### Fixed

- clear all DB connections when a connection corrupted

## [4.8.0] - 05-09-2023

### Added

- support Redlock 2.0
- configure Redis using the `redis=` config option
- support Redis Sentinel

### Changed

- deprecate using of the `redis_servers=` config option
- use RedisClient instead of Redis

## [4.7.0] - 30-08-2023

### Added

- the `owner` tag was added to metrics

## [4.6.0] - 15-08-2023

### Changed

- use gem `redlock` instead of gem `sidekiq-uniq-jobs`

## [4.5.3] - 04-08-2023

### Added

- `bin/rails g outbox:transport` generator

### Changed

- `bin/rails g outbox:inbox_item` and `bin/rails g outbox:outbox_item` are now replaced with `bin/rails g outbox:item`

## [4.5.2] - 04-07-2023

### Fixed

- merge symbolized keys in options

## [4.5.1] - 27-07-2023

### Fixed

- correct merge ordering of default options

### Changed

- changed field 'uuid' type to uuid

## [4.5.0] - 29-06-2023

### Added

- rails generator for initial configuration
- rails generator for inbox/outbox item creation

## [4.4.0] - 28-06-2023

### Added

- configured HttpHealthCheck with default port 5555

## [4.3.1] - 26-06-2023

### Fixed

- sentry middlewares autoloading issue

## [4.3.0] - 23-06-2023

### Added

- sentry tracing middlewares with optional Sentry dependency
- use wider context for job instrumentation

## [4.2.0] - 02-06-2023

### Added

- Select transports by event name

## [4.0.1] - 2023-04-07

### Fixed

- Use `camelize` instead of `classify` to constantize classes from a string

## [4.0.1] - 2023-04-07

### Changed

- Drop supporting of Rails 5.0
- Add `transports` config option


## [4.0.1] - 2023-04-07

### Changed

- Changed gem specifiers for sidekiq and sidekiq-unique-jobs from `~>` to `>=`
