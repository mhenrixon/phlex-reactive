# frozen_string_literal: true

# End-to-end request-cycle benchmark: drives the FULL Rack stack of the dummy
# app (middleware -> router -> Phlex::Reactive::ActionsController -> token verify
# -> action -> re-render -> turbo-stream) for a real reactive action POST. This
# is the number that reflects production action latency, complementing the
# micro-benches (which isolate single methods).
#
# It boots the dummy app exactly as the request specs do and POSTs through
# Rack::MockRequest — the same call-the-app primitive derailed_benchmarks uses
# internally — wrapped in benchmark-ips for throughput and memory_profiler for
# per-request allocations. derailed_benchmarks is loaded so its memory/object
# helpers are available for ad-hoc deep dives (see the performance docs page, docs/app/views/docs/pages/performance.rb).
#
#   rake bench:request
#   TEST_COUNT=500 rake bench:request

ENV["RAILS_ENV"] ||= "test"

require_relative "../../spec/dummy/config/environment"
require "active_record"
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

require "rack/mock"
require "json"
require "benchmark/ips"
require "memory_profiler"
require "derailed_benchmarks"

app = Rails.application
mock = Rack::MockRequest.new(app)

# Mint a token exactly as a component would (the app's verifier), then POST the
# reactive action body the client would send.
def sign(klass, payload)
  Phlex::Reactive.sign(payload.merge("c" => klass.name))
end

def post(mock, body)
  mock.post(
    "/reactive/actions",
    :input => body,
    "CONTENT_TYPE" => "application/json",
    "HTTP_ACCEPT" => "text/vnd.turbo-stream.html"
  )
end

# A state-backed action (no DB) and a record-backed action (GlobalID re-find +
# DB write) — the two shapes of a real round trip.
state_body = { token: sign(CounterComponent, "s" => { "count" => 1 }), act: "increment", params: {} }.to_json

todo = Todo.create!(title: "bench", done: false)
record_body = { token: sign(TodoItemComponent, "gid" => todo.to_gid.to_s), act: "toggle", params: {} }.to_json

# Sanity: both must return 200 before we benchmark, else we'd be timing an error.
%w[state record].each do
  body = it == "state" ? state_body : record_body
  status = post(mock, body).status
  abort "[bench] #{it} request returned HTTP #{status}, expected 200" unless status == 200
end

puts "\n\e[1;36mrequest cycle: POST /reactive/actions (full Rack stack)\e[0m"
puts "─" * 54
Benchmark.ips do
  it.config(time: 3, warmup: 1)
  it.report("state-backed action") { post(mock, state_body) }
  it.report("record-backed action") { post(mock, record_body) }
  it.compare!
end

puts "\n\e[1;36mallocations per request\e[0m"
puts "─" * 23
[["state-backed", state_body], ["record-backed", record_body]].each do |label, body|
  report = MemoryProfiler.report { 50.times { post(mock, body) } }
  puts format("  %-16s %8d objects/req  %10d bytes/req",
    label, report.total_allocated / 50, report.total_allocated_memsize / 50)
end
