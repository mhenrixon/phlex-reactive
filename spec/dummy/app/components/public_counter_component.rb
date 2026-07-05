# frozen_string_literal: true

# verify_authorized fixture (issue #168): a genuinely public, state-backed
# component with NO authorization — the canonical `skip_verify_authorized` case.
# The bare skip covers every action, so the guard never fires even with
# verify_authorized on.
class PublicCounterComponent < ApplicationComponent
  include Phlex::Reactive::Component

  skip_verify_authorized

  reactive_state :count
  action :increment

  def initialize(count: 0)
    @count = count
  end

  def id = "public-counter"

  def increment = @count += 1

  def view_template
    div(id:, **reactive_attrs) do
      span(data: { testid: "count" }) { @count.to_s }
      button(**mix(on(:increment), data: { testid: "inc" })) { "+" }
    end
  end
end
