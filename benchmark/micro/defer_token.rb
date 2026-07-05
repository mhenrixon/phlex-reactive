# frozen_string_literal: true

# Micro-bench: the defer-token path (issue #165) — sign_defer runs ONCE per
# deferred segment per reply (a debounced keystroke's reply can carry one), and
# verify_defer runs once per deferred fetch at the endpoint. Neither is on the
# per-render hot path (reactive_token is), but a defer-heavy screen pays them
# per interaction, so they're benched alongside the identity token to keep the
# comparison honest. The MessageVerifier HMAC dominates, as with sign/verify.
#
#   ruby benchmark/micro/defer_token.rb

require_relative "../support/boot"

state = CounterComponent.new(count: 42)
payload = state.send(:reactive_identity_payload)
token = Phlex::Reactive.sign_defer(payload)
segment = Phlex::Reactive::Defer::Segment.new(component: state, placeholder: nil, morph: false)

BenchSupport.header("defer token throughput")
BenchSupport.ips do
  it.report("sign_defer") { Phlex::Reactive.sign_defer(payload) }
  it.report("verify_defer") { Phlex::Reactive.verify_defer(token) }
  it.report("identity payload (shared shape)") { state.send(:reactive_identity_payload) }
end

BenchSupport.header("defer directive build (streams_for, fetch lane, keep-content)")
BenchSupport.ips do
  it.report("streams_for(:fetch)") { Phlex::Reactive::Defer.streams_for(segment, via: :fetch) }
end

BenchSupport.header("allocations (per call)")
Phlex::Reactive.sign_defer(payload) # warm
BenchSupport.allocations("sign_defer") { Phlex::Reactive.sign_defer(payload) }
BenchSupport.allocations("verify_defer") { Phlex::Reactive.verify_defer(token) }
BenchSupport.allocations("streams_for(:fetch)") { Phlex::Reactive::Defer.streams_for(segment, via: :fetch) }
