# frozen_string_literal: true

# The reply.defer driver (issue #165), mirroring the reps-logger shape: each
# action updates cheap state instantly and hands the expensive rollup
# (SlowTotalsComponent) to the defer machinery. `bump_sync` is the deliberate
# ANTI-example — the same work rendered synchronously — kept as the A/B
# baseline the perceived-latency spec measures against.
class DeferDemoComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count

  action :bump
  action :bump_skeleton
  action :bump_morph
  action :bump_sync
  action :bump_bare
  action :bump_eager
  action :deny_after_defer

  def initialize(count: 0)
    @count = count
  end

  def id = "defer-demo"

  # The #165 shape: cheap companion stream instantly, expensive rollup deferred
  # (keep-content default — stale totals stay visible, marked pending).
  def bump
    @count += 1
    reply.streams(mirror_stream).defer(SlowTotalsComponent.new(value: @count * 2))
  end

  # Skeleton variant: the shell replaces the totals immediately.
  def bump_skeleton
    @count += 1
    reply.streams(mirror_stream).defer(SlowTotalsComponent.new(value: @count * 2), placeholder: true)
  end

  # Morph arrival: the deferred render morphs in place when it lands.
  def bump_morph
    @count += 1
    reply.streams(mirror_stream).defer(SlowTotalsComponent.new(value: @count * 2), morph: true)
  end

  # The synchronous baseline: SAME work, ON the actor's critical path.
  def bump_sync
    @count += 1
    reply.streams(mirror_stream).also(SlowTotalsComponent.new(value: @count * 2))
  end

  # reply.defer with NO prior verb: the token rolls forward via a tiny
  # token-only stream (reply.streams), NOT a full synchronous self-render —
  # so deferring your own subject doesn't pay the acting component's render on
  # the request thread (issue #165 review fix).
  def bump_bare
    @count += 1
    reply.defer(SlowTotalsComponent.new(value: @count * 2))
  end

  # reply.replace.defer: the explicit opt-in to ALSO re-render self
  # synchronously alongside the deferred segment.
  def bump_eager
    @count += 1
    reply.replace.defer(SlowTotalsComponent.new(value: @count * 2))
  end

  # Defers, then denies (a registered authorization error): the endpoint's
  # rescue path must drop the WHOLE reply — a 403 with no defer directive, so a
  # rolled-back action can never leak a deferred render.
  def deny_after_defer
    reply.defer(SlowTotalsComponent.new(value: 0))
    raise CounterComponent::Denied, "denied after defer"
  end

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:bump), data: { testid: "defer-bump" })) { "+" }
      button(**mix(on(:bump_skeleton), data: { testid: "defer-bump-skeleton" })) { "+ (skeleton)" }
      button(**mix(on(:bump_morph), data: { testid: "defer-bump-morph" })) { "+ (morph)" }
      button(**mix(on(:bump_sync), data: { testid: "defer-bump-sync" })) { "+ (sync)" }
      span(id: "defer-count", data: { testid: "defer-count" }) { @count.to_s }
    end
  end

  private

  # The cheap companion — updates the count mirror inside this root; the
  # reply.streams token refresh keeps the root's signed token rolling.
  def mirror_stream
    %(<turbo-stream action="update" target="defer-count"><template>#{@count}</template></turbo-stream>)
  end
end
