# frozen_string_literal: true

# Exercises the confirm option (issue #52). The `delete` action is gated behind
# on(:delete, confirm: "..."). Each run bumps a `runs` counter — so a system
# spec can prove that DECLINING the prompt never runs the action (runs stays 0)
# while ACCEPTING it does (runs -> 1).
class ConfirmComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :runs

  action :delete

  def initialize(runs: 0)
    @runs = runs
  end

  def id = "confirm"

  def delete
    @runs += 1
  end

  def view_template
    div(id:, **reactive_attrs) do
      button(**mix(on(:delete, confirm: "Really delete this item?"),
        data: { testid: "delete" })) { "Delete" }
      span(data: { testid: "runs" }) { @runs.to_s }
    end
  end
end
