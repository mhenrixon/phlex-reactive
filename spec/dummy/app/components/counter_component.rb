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

  def initialize(count: 0)
    @count = count
  end

  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1
  def set(count:) = @count = count

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:decrement), data: {testid: "dec"})) { "−" }
      span(id: "counter-value", data: {testid: "count"}) { @count.to_s }
      button(**mix(on(:increment), data: {testid: "inc"})) { "+" }
      button(**mix(on(:set, count: 0), data: {testid: "reset"})) { "reset" }
    end
  end
end
