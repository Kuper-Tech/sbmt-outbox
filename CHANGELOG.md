# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] - yyyy-mm-dd

### Added

### Changed

### Fixed

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
