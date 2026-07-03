# frozen_string_literal: true

# Drives the user-visible failure surface system spec (issue #100):
#   * `boom` is DELIBERATELY undeclared → the endpoint default-denies it (403).
#     With Phlex::Reactive.error_flash configured, the rescue renders a
#     turbo-stream flash the browser SHOWS, and the client sets
#     data-reactive-error="http" on this root.
#   * `succeed` is a normal action whose re-render CLEARS data-reactive-error.
#   * `flash_now` emits a self-dismissing flash (dismiss_after:) that the
#     document-level handler removes after the timeout.
class FailureSurfaceComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :succeed
  action :flash_now

  def initialize(count: 0)
    @count = count
  end

  def id = "failure-surface"

  def succeed = @count += 1

  # A short-lived flash so the system spec can watch it appear then disappear.
  # 800ms is long enough that Capybara reliably observes it PRESENT before the
  # dismiss fires, yet short enough that have_no_css waits it out quickly.
  def flash_now
    reply.replace.flash(:notice, "gone soon", dismiss_after: 800)
  end

  def view_template
    div(id:, **reactive_attrs) do
      span(data: { testid: "count" }) { @count.to_s }
      # Undeclared action → default-deny 403 → error_flash renders a flash.
      button(**mix(on(:boom), data: { testid: "boom" })) { "boom" }
      button(**mix(on(:succeed), data: { testid: "succeed" })) { "succeed" }
      button(**mix(on(:flash_now), data: { testid: "flash-now" })) { "flash" }
    end
  end
end
