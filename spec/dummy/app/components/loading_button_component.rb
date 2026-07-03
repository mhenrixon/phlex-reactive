# frozen_string_literal: true

# Exercises declarative loading states (issue #99) end-to-end:
#
#   * on(:save, disable_with: "Saving…") — the button DISABLES and swaps its
#     text to "Saving…" the instant the request is enqueued, and reverts when the
#     round trip settles. Because a disabled button fires no further clicks, a
#     rapid double-click enqueues exactly ONE POST — so @count bumps by one, not
#     two (the disable IS the dedup; the queue only serializes, it doesn't dedupe).
#   * busy_on(:save) — a spinner element that carries data-reactive-busy only
#     while `save` is in flight, styled with pure CSS (no Ruby).
#
# The save action sleeps briefly so the browser spec can observe the disabled +
# "Saving…" + spinner state DISTINCTLY before the morph reconciles — and so a
# second click lands inside the pending window (proving the dedup).
class LoadingButtonComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count

  action :save

  def initialize(count: 0)
    @count = count
  end

  def id = "loading-button"

  def save
    # Deliberate delay so the disabled + "Saving…" + spinner state is observable
    # BEFORE the morph lands, and so a rapid second click falls inside the pending
    # window (where the disabled button swallows it) — proving the dedup-to-one.
    sleep 0.4
    @count += 1
  end

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:save, disable_with: "Saving…"), data: { testid: "save" })) { "Save" }
      # A scoped busy indicator: data-reactive-busy toggles ONLY while save is in
      # flight, so `[data-reactive-busy] { … }` reveals it with zero Ruby.
      span(**mix(busy_on(:save), data: { testid: "spinner" })) { "…" }
      span(data: { testid: "count" }) { @count.to_s }
    end
  end
end
