# frozen_string_literal: true

# Lazy initial mount fixture (issue #165): the page ships this component's
# placeholder shell; the client fetches the real content on connect through
# the defer machinery. Shares SlowTotalsComponent.render_delay_ms so the
# browser suite can make the lazy window observable.
class LazyStatsComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :scope

  reactive_lazy

  def initialize(scope: "all")
    @scope = scope
  end

  def id = "lazy-stats"

  def deferred_placeholder = %(<span data-testid="stats-shimmer">…</span>).html_safe

  def view_template
    delay = SlowTotalsComponent.render_delay_ms
    sleep(delay / 1000.0) if delay.positive?
    div(id:, **reactive_attrs) do
      span(data: { testid: "stats-value" }) { "stats:#{@scope}" }
    end
  end
end
