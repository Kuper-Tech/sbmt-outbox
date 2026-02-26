# frozen_string_literal: true

# See compatibility table at https://www.fastruby.io/blog/ruby/rails/versions/compatibility-table.html

versions_map = {
  "6.0" => %w[2.7],
  "6.1" => %w[3.0],
  "7.0" => %w[3.1],
  "7.1" => %w[3.2],
  "7.2" => %w[3.3],
  "8.0" => %w[3.3],
  "8.1" => %w[3.4]
}

rack_versions = %w[2.0 3.0]

current_ruby_version = RUBY_VERSION.split(".").first(2).join(".")

versions_map.each do |rails_version, ruby_versions|
  rack_versions.each do |rack_version|
    ruby_versions.each do |ruby_version|
      next if ruby_version != current_ruby_version

      # rack v3 supported in Rails starting from 7.1
      next if rails_version.to_f < 7.1 && rack_version.to_f > 2

      appraise "rails-#{rails_version}-rack-#{rack_version}" do
        gem "rails", "~> #{rails_version}.0"
        gem "rack", "~> #{rack_version}"
        gem "concurrent-ruby", "1.3.4" if rails_version.to_f < 7.1
        gem "pg", "1.6.2" if current_ruby_version == "2.7"
      end
    end
  end
end
