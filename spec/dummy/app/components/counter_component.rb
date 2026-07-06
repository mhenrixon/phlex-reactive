# frozen_string_literal: true

# State-backed reactive counter (no DB row). Exercises reactive_state, actions
# with and without params, and the auto-targeted re-render.
class CounterComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # A registered authorization error (see config/initializers/phlex_reactive.rb),
  # so `boom` denies inside the action and the endpoint maps it to a 403 — the
  # SAME observable outcome (status 403, client kind=http) the lifecycle-events
  # system spec watches, while keeping `boom` a DECLARED action so the render-time
  # undeclared-action guard (issue #105) doesn't reject the page on render.
  class Denied < StandardError; end

  reactive_state :count
  action :increment
  action :decrement
  action :set, params: { count: :integer }
  action :reset_with_flash
  action :bump_via_update
  action :bump_via_morph
  action :go_home
  action :bump_via_partial
  action :bump_via_with
  action :bump_via_with_self
  action :bump_with_sibling
  action :bump_with_self_stream
  action :bump_with_js
  action :boom

  def initialize(count: 0)
    @count = count
  end

  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1
  def set(count:) = @count = count

  # Reply: replace self (token refresh) + append a flash.
  def reset_with_flash
    @count = 0
    reply.replace.flash(:notice, "Reset")
  end

  # Reply: morph inner HTML (update, not replace). The rendered template still
  # carries the root's fresh data-reactive-token-value, so the token refreshes.
  def bump_via_update
    @count += 1
    reply.update
  end

  # Reply: morph the whole element in place (issue #28). Emits
  # action="replace" method="morph", so Idiomorph preserves a focused input +
  # caret. The morphed root carries the fresh token, so it must NOT be doubled
  # with a contradictory plain replace.
  def bump_via_morph
    @count += 1
    reply.morph
  end

  # Reply: client-side full navigation (no in-place stream). Targets a real
  # dummy route so the browser spec can assert the Turbo.visit landed.
  def go_home
    reply.redirect("/todos")
  end

  # Reply: update ONLY a companion target (issue #30). reply.streams emits
  # exactly the given streams and refreshes the token via a tiny reactive:token
  # stream — NO full-self replace — so a live input the user is typing into is
  # never torn down. This action is a REQUEST-spec fixture (it inspects the
  # response body, not the DOM); the end-to-end browser example is
  # PartialGridComponent.
  def bump_via_partial
    @count += 1
    reply.streams(%(<turbo-stream action="update" target="counter-mirror"><template>#{@count}</template></turbo-stream>))
  end

  # Reply: reply.with — a companion-only update that opts out of the full-self
  # replace but binds NO token_component (unlike reply.streams). Before issue
  # #180 this got a full-self replace prepended (GUARD 2), which could clobber a
  # live input; now the endpoint appends an AUTOMATIC token-only stream instead,
  # so .with and .streams converge. REQUEST-spec fixture for auto token refresh.
  def bump_via_with
    @count += 1
    reply.with(%(<turbo-stream action="update" target="counter-mirror"><template>#{@count}</template></turbo-stream>))
  end

  # Reply: reply.with whose stream ALREADY re-renders the root (the actor's own
  # self-replace, carrying the fresh token). The auto token refresh must stay
  # idempotent — no extra reactive:token, one target="counter". REQUEST-spec
  # fixture for the auto-refresh idempotency guard.
  def bump_via_with_self
    @count += 1
    reply.with(self.class.replace(count: @count).to_s)
  end

  # Reply: a partial update whose streams include ANOTHER reactive component's
  # replace — which legitimately carries its OWN data-reactive-token-value. The
  # endpoint must STILL refresh THIS component's token (the dedupe is scoped to
  # the actor's target id, not a global substring). REQUEST-spec fixture.
  def bump_with_sibling
    @count += 1
    reply.streams(TodoItemComponent.replace(Todo.create!(title: "sibling", done: false)))
  end

  # Reply: a partial update whose streams ALREADY include the actor's OWN
  # self-replace (which re-renders the root and carries the fresh token). The
  # endpoint must NOT also append a token-only stream — that would double the
  # token. Locks the idempotency carries_token_for? guarantees: a self-rendering
  # stream at the actor's own target counts as the refresh. REQUEST-spec fixture.
  def bump_with_self_stream
    @count += 1
    reply.streams(self.class.replace(count: @count))
  end

  # Reply: re-render self (morph) + push a server-side client DOM op (issue #97).
  # The reactive:js stream must ride AFTER the render stream and must NOT count as
  # a self-render (its action name is reactive:js, not replace/update) — so the
  # morph's own token refresh is untouched. REQUEST-spec fixture; the end-to-end
  # focus example is the system spec.
  def bump_with_js
    @count += 1
    reply.morph.js(js.focus("@root").dispatch("app:bumped", detail: { count: @count }))
  end

  # A denied action: raises a registered authorization error so the endpoint
  # returns 403 (client kind=http). Declared (unlike a raw undeclared action) so
  # the page renders under the issue #105 render-time guard; the 403 the browser
  # observes is unchanged.
  def boom = raise(Denied, "boom")

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:decrement), data: { testid: "dec" })) { "−" }
      span(id: "counter-value", data: { testid: "count" }) { @count.to_s }
      button(**mix(on(:increment), data: { testid: "inc" })) { "+" }
      button(**mix(on(:bump_via_update), data: { testid: "bump-update" })) { "+1 (update)" }
      button(**mix(on(:reset_with_flash), data: { testid: "reset" })) { "reset" }
      button(**mix(on(:go_home), data: { testid: "go-home" })) { "go home" }
      # `boom` denies inside the action (a registered authorization error) → the
      # endpoint returns 403, which the lifecycle-events system spec uses to
      # observe a real reactive:error (kind=http) in the browser (#79). Declared
      # so the page renders under the #105 render-time undeclared-action guard.
      button(**mix(on(:boom), data: { testid: "boom" })) { "boom" }
    end
  end
end
