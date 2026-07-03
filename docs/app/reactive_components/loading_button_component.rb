# frozen_string_literal: true

# Declarative loading states (issue #99) — no Stimulus, no bespoke JS.
#
#   * on(:save, disable_with: "Saving…") — the button DISABLES and swaps its text
#     to "Saving…" the instant the request is enqueued, reverting when the round
#     trip settles. Because a disabled button fires no further clicks, a rapid
#     double-click enqueues exactly ONE POST — so @count bumps by one, not two.
#     The disable IS the dedup (the client queue serializes, it doesn't dedupe).
#   * busy_on(:save) — a spinner element that carries data-reactive-busy only
#     while `save` is in flight, styled with pure CSS (daisyUI loading-spinner).
#
# The action is intentionally FAST server-side — flip the latency toggle above it
# to actually SEE the disabled + "Saving…" + spinner window on localhost.
class LoadingButtonComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :save

  def initialize(count: 0)
    @count = count
  end

  def id = 'loading-button'

  def save = @count += 1

  def view_template
    # The spinner is present in the DOM always; this scoped rule reveals it ONLY
    # while busy_on marks it with data-reactive-busy — pure CSS, no Ruby toggle.
    style do
      # Static CSS, no user input — Phlex safe(), not Rails html_safe.
      css = '[data-testid="spinner"]{display:none} ' \
            '[data-testid="spinner"][data-reactive-busy]{display:inline-block}'
      raw(safe(css)) # rubocop:disable Rails/OutputSafety
    end
    div(**reactive_root(class: 'flex items-center gap-3')) do
      button(**mix(on(:save, disable_with: 'Saving…'),
                   class: 'btn btn-sm btn-primary', data: { testid: 'save' })) { 'Save' }
      # A scoped busy indicator: data-reactive-busy toggles ONLY while save is in
      # flight, so daisyUI's spinner shows with zero Ruby.
      span(**mix(busy_on(:save),
                 class: 'loading loading-spinner loading-sm', data: { testid: 'spinner' }))
      span(class: 'text-sm opacity-70', data: { testid: 'saved-count' }) do
        plain 'Saved '
        span { @count.to_s }
        plain ' times'
      end
    end
  end
end
