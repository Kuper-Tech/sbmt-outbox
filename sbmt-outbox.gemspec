# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "sbmt/outbox/version"

Gem::Specification.new do |s|
  s.name = "sbmt-outbox"
  s.version = Sbmt::Outbox::VERSION
  s.authors = ["Misha Merkushin"]
  s.email = ["mikhail.merkushin@sbermarket.ru"]
  s.summary = "Outbox service"
  s.description = "A service that uses a relational database inserts messages/events into an outbox table as part of the local transaction."

  s.files = Dir["{app,config,lib,exe}/**/*", "Rakefile", "README.md"]
  s.bindir = "exe"
  s.executables = s.files.grep(%r{^exe/}) { |f| File.basename(f) }

  s.required_ruby_version = ">= 2.5"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if s.respond_to?(:metadata)
    s.metadata["allowed_push_host"] = "https://nexus.sbmt.io"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  s.post_install_message = "
  Outbox gem starting 4.3.0 uses internal Sentry-tracing middlewares for job instrumentation.

  \e[1;33mIMPORTANT:\e[0m SentryTracingItemProcessMiddleware / SentryTracingBatchProcessMiddleware \e[1;33mSHOULD BE REMOVED\e[0m from your application's codebase!
  If your application uses custom Outbox-middlewares for instrumentation, please check there are no functionality interferences.

  "

  s.add_dependency "after_commit_everywhere", "~> 1.2"
  s.add_dependency "cutoff", "~> 0.5"
  s.add_dependency "dry-initializer", "~> 3.0"
  s.add_dependency "dry-monads", "~> 1.3"
  s.add_dependency "exponential-backoff", "~> 0.0"
  s.add_dependency "rails", ">= 5.1"
  s.add_dependency "schked", ">= 0.3", "< 2"
  s.add_dependency "sidekiq", ">= 5.2"
  s.add_dependency "sidekiq-unique-jobs", ">= 7.1"
  s.add_dependency "ruby2_keywords" # Remove this on Ruby 2.7
  s.add_dependency "yabeda", "~> 0.8"
  s.add_dependency "thor"
  s.add_dependency "redlock"

  s.add_development_dependency "appraisal"
  s.add_development_dependency "bundler"
  s.add_development_dependency "combustion"
  s.add_development_dependency "fabrication"
  s.add_development_dependency "pg"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "rspec-rails"
  s.add_development_dependency "rspec_junit_formatter"
  s.add_development_dependency "rubocop"
  s.add_development_dependency "rubocop-rails"
  s.add_development_dependency "rubocop-rspec"
  s.add_development_dependency "rubocop-performance"
  s.add_development_dependency "standard", ">= 1.7"
  s.add_development_dependency "zeitwerk"
  s.add_development_dependency "sentry-rails", "> 5.2.0"
end
