# frozen_string_literal: true

# Drives the latency-simulator system spec (issue #102). The `bump` action is
# FAST server-side (no sleep) — exactly the localhost case where the ~5ms round
# trip makes aria-busy flash by unobservably. The spec enables the simulator
# (PhlexReactive.enableLatencySim(ms)) and then asserts aria-busy IS visible
# during the injected client-side delay — proving the sim opens a real,
# observable busy window without any server-side stall.
class LatencyComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count

  action :bump

  def initialize(count: 0)
    @count = count
  end

  def id = "latency"

  # No sleep: the busy window is created purely by the client latency simulator,
  # not by a slow server action.
  def bump = @count += 1

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:bump), data: { testid: "bump" })) { "Bump" }
      span(data: { testid: "count" }) { @count.to_s }
    end
  end
end
