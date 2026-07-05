# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"

group :development do
  gem "rubocop", "~> 1.80", require: false
  gem "rubocop-capybara", "~> 2.21", require: false
  gem "rubocop-performance", "~> 1.26", require: false
  gem "rubocop-rake", "~> 0.7", require: false
  gem "rubocop-rspec", "~> 3.0", require: false
  gem "rubocop-thread_safety", "~> 0.7", require: false
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
  # Performance measurement. The micro-benches (benchmark/micro/*) isolate the hot
  # methods (render, reactive_token, param coercion) with benchmark-ips for
  # throughput and memory_profiler for allocations. The request-cycle bench
  # (benchmark/request/*) drives the dummy app through derailed_benchmarks for
  # end-to-end latency + memory. See docs/performance.md and `rake -T bench`.
  gem "benchmark-ips", "~> 2.13", require: false
  gem "derailed_benchmarks", "~> 2.1", require: false
  gem "memory_profiler", "~> 1.0", require: false
  gem "stackprof", "~> 0.2", require: false # derailed_benchmarks profiling backend

  gem "actioncable", ">= 7.1", "< 9.0"
  gem "activejob", ">= 7.1", "< 9.0"
  gem "activerecord", ">= 7.1", "< 9.0"
  # ActiveStorage backs the file/multipart upload fixture (issue #34). Dev/test
  # only — phlex-reactive itself doesn't depend on it; the dummy app uses it to
  # attach an uploaded file from a reactive action.
  gem "activestorage", ">= 7.1", "< 9.0"
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
  # pgbus requires Ruby >= 3.3 — satisfied by phlex-reactive's 3.4 floor.
  if (pgbus_path = ENV.fetch("PGBUS_PATH", nil))
    gem "pgbus", path: pgbus_path, require: false
  else
    gem "pgbus", ">= 0.9.4", require: false
  end
  gem "pg", "~> 1.5", require: false # pgbus needs PostgreSQL

  # The read-only diagnostic MCP server (issue #168) is OPTIONAL and lazy — it is
  # NOT a gemspec runtime dependency (Phlex::Reactive::MCP.load! requires it on
  # demand with a helpful message when missing, the pgbus pattern). Here only so
  # the mcp_spec and `bin/rails phlex_reactive:mcp` can exercise it; a host app
  # adds `gem "mcp"` itself when it wants the server.
  gem "mcp", require: false
end
