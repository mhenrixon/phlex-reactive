# frozen_string_literal: true

# State-backed reactive counter (no DB row). Exercises reactive_state, actions
# with and without params, and the auto-targeted re-render.
class CounterComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :increment
  action :decrement
  action :set, params: { count: :integer }
  action :reset_with_flash
  action :bump_via_update
  action :bump_via_morph
  action :go_home
  action :bump_via_partial
  action :bump_with_sibling

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

  # Reply: a partial update whose streams include ANOTHER reactive component's
  # replace — which legitimately carries its OWN data-reactive-token-value. The
  # endpoint must STILL refresh THIS component's token (the dedupe is scoped to
  # the actor's target id, not a global substring). REQUEST-spec fixture.
  def bump_with_sibling
    @count += 1
    reply.streams(TodoItemComponent.replace(Todo.create!(title: "sibling", done: false)))
  end

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:decrement), data: { testid: "dec" })) { "−" }
      span(id: "counter-value", data: { testid: "count" }) { @count.to_s }
      button(**mix(on(:increment), data: { testid: "inc" })) { "+" }
      button(**mix(on(:bump_via_update), data: { testid: "bump-update" })) { "+1 (update)" }
      button(**mix(on(:reset_with_flash), data: { testid: "reset" })) { "reset" }
      button(**mix(on(:go_home), data: { testid: "go-home" })) { "go home" }
    end
  end
end
