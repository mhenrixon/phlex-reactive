# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"

group :development do
  gem "rubocop", "~> 1.21", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "standard", "~> 1.3", require: false
end

# Performance measurement. The micro-benches (benchmark/micro/*) isolate the hot
# methods (render, reactive_token, param coercion) with benchmark-ips for
# throughput and memory_profiler for allocations. The request-cycle bench
# (benchmark/request/*) drives the dummy app through derailed_benchmarks for
# end-to-end latency + memory. See docs/performance.md and `rake -T bench`.
group :development, :test do
  gem "benchmark-ips", "~> 2.13", require: false
  gem "memory_profiler", "~> 1.0", require: false
  gem "derailed_benchmarks", "~> 2.1", require: false
  gem "stackprof", "~> 0.2", require: false # derailed_benchmarks profiling backend
end

group :test do
  gem "rspec", "~> 3.0"
  gem "rspec-rails", "~> 7.0"

  # System tests
  gem "capybara", require: false
  gem "capybara-playwright-driver", require: false
  gem "puma", require: false
  # Falcon is the real-server fallback for the browser suite (CAPYBARA_SERVER=falcon)
  # — an async, production-grade alternative to Puma. No webrick (not a real server).
  gem "falcon", require: false
end

group :development, :test do
  gem "actioncable", ">= 7.1", "< 9.0"
  gem "activejob", ">= 7.1", "< 9.0"
  gem "activerecord", ">= 7.1", "< 9.0"
  gem "sqlite3", ">= 1.4"

  # pgbus is NOT a runtime dependency (it stays out of the gemspec — broadcasts
  # route through Turbo::StreamsChannel, which pgbus patches, so phlex-reactive
  # works on Action Cable OR pgbus). We pull it in here ONLY to develop and test
  # against pgbus's reactive Streams primitives (exclude:/broadcast_render/
  # auto-presence/typed-events/coalescing/msg_id) plus the exclude:/visible_to:/
  # event: forwarding through the Turbo broadcast helpers — both shipped in
  # pgbus 0.9.4. phlex-reactive 0.2.0's actor-echo suppression needs them.
  #
  # For fast local iteration against your own checkout, set PGBUS_PATH:
  #   PGBUS_PATH=~/Code/mhenrixon/pgbus bundle install
  #
  # pgbus requires Ruby >= 3.3, but phlex-reactive's runtime supports 3.2
  # (it's dev-only here). Skip it on 3.2 so the 3.2 CI matrix job still resolves.
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3")
    if (pgbus_path = ENV["PGBUS_PATH"])
      gem "pgbus", path: pgbus_path, require: false
    else
      gem "pgbus", ">= 0.9.4", require: false
    end
    gem "pg", "~> 1.5", require: false # pgbus needs PostgreSQL
  end
end
