# frozen_string_literal: true

# Exercises the authorization-error path (issue #82). `moderate` always raises
# NotAllowed; the verbose_errors request spec registers that class in
# Phlex::Reactive.authorization_errors and asserts the endpoint's diagnostic
# 403 names the error class and the action.
class ModeratedComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  class NotAllowed < StandardError; end

  reactive_state :noop

  action :moderate

  def initialize(noop: nil)
    @noop = noop
  end

  def id = "moderated"

  def moderate
    raise NotAllowed, "not allowed"
  end

  def view_template
    div(id:, **reactive_attrs) { "moderated" }
  end
end
