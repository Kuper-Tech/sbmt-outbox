# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased] - yyyy-mm-dd

### Added

### Changed

### Fixed

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
