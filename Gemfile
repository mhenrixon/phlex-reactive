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

  # pgbus is NOT a runtime dependency (it stays out of the gemspec — broadcasts
  # route through Turbo::StreamsChannel, which pgbus patches, so phlex-reactive
  # works on Action Cable OR pgbus). We pull it in here ONLY to develop and test
  # against the unreleased reactive primitives (pgbus #173:
  # exclude:/broadcast_render/auto-presence/typed-events/coalescing/msg_id).
  # Switch to the released gem once those ship.
  #
  # Default: git `main` (works in CI / for anyone cloning). For fast local
  # iteration against your own checkout — and so it doesn't fight whatever
  # branch you have checked out — set PGBUS_PATH:
  #   PGBUS_PATH=~/Code/mhenrixon/pgbus bundle install
  # pgbus requires Ruby >= 3.3, but phlex-reactive's runtime supports 3.2
  # (it's dev-only here). Skip it on 3.2 so the 3.2 CI matrix job still resolves.
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
    if (pgbus_path = ENV["PGBUS_PATH"])
      gem "pgbus", path: pgbus_path, require: false
    else
      gem "pgbus", github: "mhenrixon/pgbus", branch: "main", require: false
    end
    gem "pg", "~> 1.5", require: false # pgbus needs PostgreSQL
  end
end
