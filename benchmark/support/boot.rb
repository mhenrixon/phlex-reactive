# frozen_string_literal: true

# Shared boot for the micro-benchmarks. Boots the dummy Rails app (so the
# renderer controller, view context, and example components are all available)
# and loads the in-memory schema — the same setup spec/rails_helper.rb uses, so
# a bench measures the real render/coerce path, not a stub.
#
#   ruby benchmark/micro/render.rb
#   rake bench:micro
#
# Off-Rails micro-benches (signing only) can skip this and require
# "phlex/reactive" directly, but the render path needs the full app.

ENV["RAILS_ENV"] ||= "test"

require_relative "../../spec/dummy/config/environment"

require "active_record"
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

require "benchmark/ips"
require "memory_profiler"

module BenchSupport
  module_function

  # Run a benchmark-ips comparison over the given labelled procs and print a
  # comparison table. `time:`/`warmup:` kept short so the full suite stays fast
  # in CI; bump them locally when chasing a small delta.
  def ips(time: 2, warmup: 1)
    Benchmark.ips do |x|
      x.config(time: time, warmup: warmup)
      yield x
      x.compare!
    end
  end

  # Print the total allocated objects/bytes for one labelled proc — the number
  # that actually moves when we kill a per-call allocation. Returns the report
  # so a caller can assert on it if needed.
  def allocations(label)
    report = MemoryProfiler.report { yield }
    puts format(
      "  %-32s %8d objects  %10d bytes (retained: %d objects)",
      label, report.total_allocated, report.total_allocated_memsize, report.total_retained
    )
    report
  end

  def header(title)
    puts "\n\e[1;36m#{title}\e[0m"
    puts "─" * title.length
  end
end
