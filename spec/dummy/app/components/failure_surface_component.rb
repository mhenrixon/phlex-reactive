# frozen_string_literal: true

# Drives the user-visible failure surface system spec (issue #100):
#   * `boom` denies inside a DECLARED action (a registered authorization error)
#     → the endpoint returns 403. With Phlex::Reactive.error_flash configured,
#     the rescue renders a turbo-stream flash the browser SHOWS, and the client
#     sets data-reactive-error="http" on this root. It is DECLARED (not a raw
#     undeclared action) so the page renders under the render-time
#     undeclared-action guard (issue #105); the 403 the browser sees is unchanged.
#   * `succeed` is a normal action whose re-render CLEARS data-reactive-error.
#   * `flash_now` emits a self-dismissing flash (dismiss_after:) that the
#     document-level handler removes after the timeout.
class FailureSurfaceComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Registered in config/initializers/phlex_reactive.rb so `boom`'s denial maps
  # to a 403 (client kind=http) instead of a 500.
  class Denied < StandardError; end

  reactive_state :count
  action :succeed
  action :flash_now
  action :boom

  def initialize(count: 0)
    @count = count
  end

  def id = "failure-surface"

  def succeed = @count += 1

  # Denies inside the action → 403 (client kind=http), the failure the system
  # spec drives. Declared so the page renders under the issue #105 guard.
  def boom = raise(Denied, "boom")

  # A short-lived flash so the system spec can watch it appear then disappear.
  # 800ms is long enough that Capybara reliably observes it PRESENT before the
  # dismiss fires, yet short enough that have_no_css waits it out quickly.
  def flash_now
    reply.replace.flash(:notice, "gone soon", dismiss_after: 800)
  end

  def view_template
    div(id:, **reactive_attrs) do
      span(data: { testid: "count" }) { @count.to_s }
      # Denied action → 403 → error_flash renders a flash. Declared (see class
      # header) so the page renders under the issue #105 render-time guard.
      button(**mix(on(:boom), data: { testid: "boom" })) { "boom" }
      button(**mix(on(:succeed), data: { testid: "succeed" })) { "succeed" }
      button(**mix(on(:flash_now), data: { testid: "flash-now" })) { "flash" }
    end
  end
end
