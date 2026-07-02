# frozen_string_literal: true

# Micro-bench: the component re-render path (the hottest server work in an
# action round trip). `to_stream_replace` builds a Turbo stream from the
# component, which needs a view context. We memoize that context per class, so
# this bench measures the steady-state cost AND, with PHLEX_REACTIVE_NO_CACHE=1,
# the un-memoized cost for an apples-to-apples before/after.
#
#   ruby benchmark/micro/render.rb
#   PHLEX_REACTIVE_NO_CACHE=1 ruby benchmark/micro/render.rb   # the "before"

require_relative "../support/boot"

# Optional "before" mode: flush the cache on every call so we measure the cost
# of rebuilding the view context per render (the pre-optimization behavior).
no_cache = ENV["PHLEX_REACTIVE_NO_CACHE"] == "1"
reset = -> { CounterComponent.reset_turbo_view_context! if no_cache }

BenchSupport.header("render: CounterComponent#to_stream_replace#{" (NO CACHE)" if no_cache}")

BenchSupport.ips do
  it.report("to_stream_replace") do
    reset.call
    CounterComponent.new(count: 1).to_stream_replace
  end
end

BenchSupport.header("allocations per render")
CounterComponent.new(count: 1).to_stream_replace # warm the cache for the cached run
BenchSupport.allocations("to_stream_replace") do
  reset.call
  CounterComponent.new(count: 1).to_stream_replace
end

# render_component is the lightweight phlex-rails render_in path (vs the old
# ActionController renderer.render). This isolates the pure render cost — the
# win that matters MOST for broadcasts, which have NO HTTP round trip to
# amortize against. Each broadcast_*_to CALL renders once and all subscribers
# of that stream share the payload; the cost multiplies per call (K stream
# keys = K renders) and per viewer for visible_to:-style per-viewer content.
BenchSupport.header("render_component (the broadcast/fan-out unit)")
BenchSupport.ips do
  it.report("render_component") { CounterComponent.render_component(CounterComponent.new(count: 1)) }
end
BenchSupport.allocations("render_component") do
  CounterComponent.render_component(CounterComponent.new(count: 1))
end
