# frozen_string_literal: true

require "rails_helper"

# The perceived-performance contract of reply.defer (issue #165), measured, not
# asserted by vibes: with a deliberately expensive segment (SlowTotalsComponent
# dialed to ~120ms of render cost), the SYNC reply pays that cost on the
# actor's critical path and the DEFERRED reply does not. This is the request-
# level half of the A/B (the browser half lives in spec/system/defer_spec.rb);
# the margins are deliberately generous — the sleep dominates, so the assert is
# about WHERE the cost lands, never about micro-timing.
#
# The honest framing (docs say the same): defer trades a slightly WORSE
# time-to-full-content (+1 round trip) for a much better actor reply latency.
# This spec pins the second half; the deferred fetch itself is exercised in
# deferred_render_spec.rb.
RSpec.describe "deferred reply latency (A/B)", type: :request do
  DELAY_MS = 120

  around do |example|
    SlowTotalsComponent.render_delay_ms = DELAY_MS
    example.run
  ensure
    SlowTotalsComponent.render_delay_ms = 0
  end

  def elapsed_ms
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
  end

  it "the deferred reply returns WITHOUT paying the expensive render; the sync baseline pays it" do
    deferred_ms = elapsed_ms do
      post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("reactive:defer")
    end

    sync_ms = elapsed_ms do
      post_action(DeferDemoComponent, act: :bump_sync, payload: { "s" => { "count" => 0 } })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(">2<")
    end

    # The sync reply must carry at least the render delay; the deferred reply
    # must dodge most of it. Both margins leave ~half the delay of headroom for
    # CI noise — the claim is "the cost moved off the reply", not a timing.
    expect(sync_ms).to be >= DELAY_MS
    expect(deferred_ms).to be < sync_ms - (DELAY_MS / 2)
  end

  it "the deferred FETCH pays the render cost off the actor's critical path (the trade is visible)" do
    token = Phlex::Reactive.sign_defer({ "c" => "SlowTotalsComponent", "s" => { "value" => 1 } })

    fetch_ms = elapsed_ms do
      post Phlex::Reactive.defer_path, params: { token: }.to_json,
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    expect(fetch_ms).to be >= DELAY_MS # the cost didn't vanish — it moved
  end
end
