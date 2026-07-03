# frozen_string_literal: true

# Micro-bench: reactive_token, which signs the component's identity payload on
# EVERY render (it's spread into the root element via reactive_attrs). We cache
# the ivar symbols + string keys per class so the per-render path no longer
# allocates a Symbol/String per state key. The signing itself (MessageVerifier
# HMAC) dominates and is unavoidable — this isolates the assembly cost around it.
#
#   ruby benchmark/micro/token.rb

require_relative "../support/boot"

state = CounterComponent.new(count: 42)          # state-backed ({c, s})
todo = Todo.create!(title: "t", done: false)
record = TodoItemComponent.new(todo:)            # record-backed ({c, gid})

BenchSupport.header("reactive_token throughput")
BenchSupport.ips do
  it.report("state-backed token") { state.send(:reactive_token) }
  it.report("record-backed token") { record.send(:reactive_token) }
end

BenchSupport.header("reactive_token allocations (per call)")
state.send(:reactive_token) # warm the class-level caches
BenchSupport.allocations("state-backed") { state.send(:reactive_token) }
BenchSupport.allocations("record-backed") { record.send(:reactive_token) }

BenchSupport.header("on() trigger attrs (no explicit params — the common case)")
# Warm like line 24 above: under verbose_errors on() consults reactive_actions,
# whose Registry resolution (issue #115) memoizes per class on FIRST read — a
# one-time, class-load-shaped cost. This measures the per-call steady state.
state.send(:on, :increment)
BenchSupport.allocations("on(:increment)") { state.send(:on, :increment) }
