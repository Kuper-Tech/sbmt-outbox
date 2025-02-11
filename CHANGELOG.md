# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] - yyyy-mm-dd

### Added

### Changed

### Fixed

## [6.19.0] - 2025-02-11

### Added

- Querying minimum `created_at` for deletion now uses a replica database to reduce primary database load

## [6.18.0] - 2025-02-04

### Added

- Add failed item caching in case of unrecoverable database conn issues
- Add `retry_latency` metric to measure retries

### Fixed

- Fix item processing cutoff timeout to be less than generic redis lock timeout

## [6.17.0] - 2025-01-30

### Added

- Added options for configuring jobs to remove old items:
  - `deletion_time_window` - 4 hours

### Changed

- Change condition for job deleted items

## [6.16.0] - 2025-01-28

### Added

- Add `polling_item_middlewares`

## [6.15.0] - 2025-01-23

### Added

- Add rake tasks:
  - rake outbox:delete_items
  - rake outbox:update_status_items

## [6.14.0] - 2025-01-20

### Added

- Added options for configuring jobs to remove old items:
  - `deletion_batch_size` - default 1_000
  - `deletion_sleep_time` - pauses between `batch_size`
  - `min_retention_period` - for items with statuses: `failed` and `discarded`
  - `delivered_min_retention_period` - for items with statuses: `delivered`

## [6.13.1] - 2025-01-15

### Fixed

- Fix support enum for rails < 7

## [6.13.0] - 2025-01-15

### Added

- Add metrics `delete_latency` and `deleted_counter`

## [6.12.0] - 2025-01-10

### Added

- Random seconds have been added to the item removal tasks to prevent tasks from running simultaneously
- Add option `retention_delivered_items` to remove successful items. Default equals option `retention`

### Changed

- `retention` removes items with statuses: `failed` and `discarded`

## [6.11.0] - 2024-12-23

### Added

- Add support of Rails 8.0

### Changed

- Dropped support of Rails 5.2

## [6.10.5] - 2024-11-05

### Fixed

- use Nexus URL environment variable for internal releases

## [6.10.4] - 2024-10-29

### Fixed

- fix deleting stale items from Postgis

## [6.10.3] - 2024-10-22

### Fixed

- fix deleting stale items from MySQL and PostgreSQL

## [6.10.2] - 2024-09-30

### Fixed

- change `DEFAULT_PARTITION_STRATEGY` to string

## [6.10.1] - 2024-09-23

### Fixed

- log OTEL `trace_id`

## [6.10.0] - 2024-09-19

### Changed

- Renamed `backtrace` log tag to `stacktrace`

### Fixed

- Fixed handling of errors if database is not available

## [6.9.0] - 2024-09-13

### Added

- Replaced index `add_index :#{table_name}, [:status, :bucket, :errors_count]` to `add_index :#{table_name}, [:status, :id, :bucket], algorithm: :concurrently, include: [:errors_count]`

## [6.8.0] - 2024-09-05

### Added

- Add outbox context to ActiveRecord query log tags

## [6.7.0] - 2024-08-29

### Added

- Implement an ability to create outbox items in batches through `Sbmt::Outbox::CreateOutboxBatch`

## [6.6.0] - 2024-06-17

### Added

- add option `strict_order`

### Fixed
- fix README

## [6.5.0] - 2024-06-05

### Added

- use db replica to select stale item ids

### Fixed

- fix undefined local variable or method labels for Sbmt::Outbox::V2::Poller

## [6.4.3] - 2024-05-16

### Fixed

- replace `/` with `-` in label `name` in outbox_last_stored_event_id / outbox_created_counter

## [6.4.2] - 2024-05-07

### Fixed

- replace `/` with `-` in label `name` in box metrics

## [6.4.1] - 2024-05-06

### Fixed

- Add process the SIGQUIT signal.

## [6.4.0] - 2024-05-02

### Added
- added autostart of the yabeda server via the `enabled` option
- added disabling autorun of probes via the `enabled` option

## [6.3.1] - 2024-05-01

### Added

- Add box_id to make it url safe for use in the API.

## [6.3.0] - 2024-04-18

### Added

- Add support for [Outbox UI](https://github.com/SberMarket-Tech/sbmt-outbox-ui)
- Add ability to pause poller v2

## [6.2.0] - 2024-04-17

### Added
- buckets for the histogram are brought to a single form

## [6.1.0] - 2024-04-15

### Added
- Add `owner` label to `job_counter` metric

## [6.0.1] - 2024-03-28

### Added
- `PollThrottler::RateLimited` is now per box-based

### Fixed
- `BRPOP` timeout default for queue processing

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
