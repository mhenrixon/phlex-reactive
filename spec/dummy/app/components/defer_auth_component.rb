# frozen_string_literal: true

# A defer target that AUTHORIZES ON RENDER (issue #186 contract test). A deferred
# render never runs an action, so the :unauthorized defer outcome comes from a
# component that guards its own visibility — from_identity here raises a registered
# authorization error (mapped to 403 via config/initializers/phlex_reactive.rb).
class DeferAuthComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Registered in the dummy initializer so a raise maps to a 403 + the defer
  # instrument's :unauthorized outcome, not a 500.
  class Denied < StandardError; end

  reactive_state :value

  def self.from_identity(_payload)
    raise Denied, "not allowed to render"
  end

  def initialize(value: 0)
    @value = value
  end

  def id = "defer-auth"

  def view_template = div(id:, **reactive_attrs) { @value.to_s }
end
