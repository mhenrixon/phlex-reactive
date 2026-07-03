# frozen_string_literal: true

# Drives the timeout + offline system spec (issue #101):
#   * `slow` sleeps LONGER than the page's shortened phlex-reactive-timeout meta,
#     so the client aborts the fetch (kind:"timeout") — proving the queue does
#     NOT wedge: a subsequent `ping` still round-trips.
#   * `ping` returns immediately (a normal re-render) and is what the spec fires
#     AFTER the timeout to prove the per-component queue recovered.
class NetworkStatusComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :slow
  action :ping

  def initialize(count: 0)
    @count = count
  end

  def id = "network-status"

  # Sleeps well past the spec's shortened timeout meta so the CLIENT aborts the
  # fetch. The server keeps working (it eventually finishes), but the client has
  # already moved on — the queue is not wedged.
  def slow
    sleep 2.5
    @count += 1
  end

  def ping = @count += 1

  def view_template
    div(id:, **reactive_attrs) do
      span(data: { testid: "count" }) { @count.to_s }
      button(**mix(on(:slow), data: { testid: "slow" })) { "slow" }
      button(**mix(on(:ping), data: { testid: "ping" })) { "ping" }
    end
  end
end
