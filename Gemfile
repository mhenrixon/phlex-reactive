# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"

group :development do
  gem "rubocop", "~> 1.21", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "standard", "~> 1.3", require: false
end

group :test do
  gem "rspec", "~> 3.0"
  gem "rspec-rails", "~> 7.0"

  # System tests
  gem "capybara", require: false
  gem "capybara-playwright-driver", require: false
  gem "puma", require: false
  gem "webrick", require: false
end

group :development, :test do
  gem "actioncable", ">= 7.1", "< 9.0"
  gem "activejob", ">= 7.1", "< 9.0"
  gem "activerecord", ">= 7.1", "< 9.0"
  gem "sqlite3", ">= 1.4"
end
