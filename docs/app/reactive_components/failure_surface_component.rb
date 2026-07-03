# frozen_string_literal: true

# The user-visible failure surface (issue #100). Reactive actions don't only
# succeed — this shows what an adopter gets for free when one fails:
#   * `boom` denies inside a DECLARED action (a registered authorization error) →
#     the endpoint returns 403. With Phlex::Reactive.error_flash configured, the
#     rescue renders a turbo-stream flash the browser SHOWS, and the client sets
#     data-reactive-error="http" on this root (style it with CSS).
#   * `succeed` is a normal action whose re-render CLEARS data-reactive-error.
#   * `flash_now` emits a self-dismissing flash (dismiss_after:) the document-level
#     handler removes after the timeout.
class FailureSurfaceComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Registered in config/initializers/phlex_reactive.rb so `boom`'s denial maps to
  # a clean 403 (client kind=http) instead of a 500.
  class Denied < StandardError; end

  reactive_state :count
  action :succeed
  action :flash_now
  action :boom

  def initialize(count: 0)
    @count = count
  end

  def id = 'failure-surface'

  def succeed = @count += 1

  # Denies inside the action → 403 (client kind=http), the failure the demo shows.
  # Declared so the page renders under the render-time undeclared-action guard.
  def boom = raise(Denied, 'boom')

  # A short-lived flash so the demo can watch it appear then disappear.
  def flash_now
    reply.replace.flash(:notice, 'Saved — this toast self-dismisses', dismiss_after: 2500)
  end

  def view_template
    # Reveal the error banner ONLY while the root carries data-reactive-error —
    # pure CSS, no Ruby toggle.
    style do
      css = '[data-testid="error-banner"]{display:none} ' \
            '[data-reactive-error] [data-testid="error-banner"]{display:block}'
      raw(safe(css)) # rubocop:disable Rails/OutputSafety
    end
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      div(class: 'alert alert-error', role: 'alert', data: { testid: 'error-banner' }) do
        'The last action failed — data-reactive-error is set on the root.'
      end

      div(class: 'flex items-center gap-3') do
        span(class: 'text-sm opacity-70') do
          plain 'Succeeded '
          span(data: { testid: 'count' }) { @count.to_s }
          plain ' times'
        end
      end

      div(class: 'flex gap-2') do
        button(**mix(on(:succeed), class: 'btn btn-sm btn-success', data: { testid: 'succeed' })) { 'Succeed' }
        button(**mix(on(:boom), class: 'btn btn-sm btn-error', data: { testid: 'boom' })) { 'Trigger a failure' }
        button(**mix(on(:flash_now), class: 'btn btn-sm', data: { testid: 'flash-now' })) { 'Self-dismissing flash' }
      end

      # The flash target for the error_flash + dismiss_after: toasts.
      div(id: 'flash', class: 'flex flex-col gap-1', data: { testid: 'flash' })
    end
  end
end
