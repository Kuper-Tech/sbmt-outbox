# frozen_string_literal: true

source ENV.fetch("NEXUS_PUBLIC_SOURCE_URL", "https://rubygems.org")

gemspec

current_ruby_version = RUBY_VERSION.split(".").first(2).join(".")

puts ["!!!!", current_ruby_version].inspect
if current_ruby_version == "2.7"
  gem "pg", "= 1.6.0"
end
