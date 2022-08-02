# frozen_string_literal: true

# See compatibility table at https://www.fastruby.io/blog/ruby/rails/versions/compatibility-table.html

if RUBY_VERSION > "2.4"
  if RUBY_VERSION < "2.6"
    appraise "rails-5.0" do
      gem "rails", "~> 5.0.0"
    end

    appraise "rails-5.1" do
      gem "rails", "~> 5.1.0"
    end
  end

  if RUBY_VERSION < "2.7"
    appraise "rails-5.2" do
      gem "rails", "~> 5.2.0"
    end
  end

  if RUBY_VERSION < "3.0"
    appraise "rails-6.0" do
      gem "rails", "~> 6.0.0"
    end
  end

  if RUBY_VERSION < "3.1"
    appraise "rails-6.1" do
      gem "rails", "~> 6.1.0"
    end
  else
    raise "Unsupported Ruby version: #{RUBY_VERSION}"
  end
else
  raise "Unsupported Ruby version: #{RUBY_VERSION}"
end
