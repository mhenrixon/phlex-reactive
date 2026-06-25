# frozen_string_literal: true

# State-backed reactive counter (no DB row). Exercises reactive_state, actions
# with and without params, and the auto-targeted re-render.
class CounterComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :increment
  action :decrement
  action :set, params: {count: :integer}
  action :reset_with_flash
  action :bump_via_update
  action :go_home

  def initialize(count: 0)
    @count = count
  end

  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1
  def set(count:) = @count = count

  # Response: replace self (token refresh) + append a flash.
  def reset_with_flash
    @count = 0
    Phlex::Reactive::Response.replace(self).flash(:notice, "Reset")
  end

  # Response: morph inner HTML (update, not replace). The rendered template still
  # carries the root's fresh data-reactive-token-value, so the token refreshes.
  def bump_via_update
    @count += 1
    Phlex::Reactive::Response.update(self)
  end

  # Response: client-side full navigation (no in-place stream). Targets a real
  # dummy route so the browser spec can assert the Turbo.visit landed.
  def go_home
    Phlex::Reactive::Response.redirect("/todos")
  end

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:decrement), data: {testid: "dec"})) { "−" }
      span(id: "counter-value", data: {testid: "count"}) { @count.to_s }
      button(**mix(on(:increment), data: {testid: "inc"})) { "+" }
      button(**mix(on(:reset_with_flash), data: {testid: "reset"})) { "reset" }
      button(**mix(on(:go_home), data: {testid: "go-home"})) { "go home" }
    end
  end
end
