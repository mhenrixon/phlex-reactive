# frozen_string_literal: true

# Issue #179: DECLARATIVE conditional confirm. The save action warns ONLY when
# the `total` field is 0 — confirm: { when: { total: 0 }, message: } compiles the
# reactive_show conditions language (0 = equals) and the client evaluates it over
# the collected fields. A non-zero total submits silently; a zero total prompts.
# `runs` bumps on save so the system spec can prove: declined-when-zero never
# runs, accepted-when-zero runs, and a clean (non-zero) total runs with no dialog.
class ConditionalConfirmComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :runs

  action :save, params: { total: :integer }

  def initialize(runs: 0)
    @runs = runs
  end

  def id = "conditional-confirm"

  def save(total:)
    @runs += 1
  end

  def view_template
    # reactive_root already binds id + controller + token — do NOT also spread
    # reactive_attrs (that double-emits the token → a "token token" POST → 400).
    div(**reactive_root) do
      # The field whose value drives the conditional confirm ([name="total"]).
      input(name: "total", value: "0", data: { testid: "total" })

      button(**mix(
        on(:save, confirm: { when: { total: 0 }, message: "Total is 0 — continue?" }),
        data: { testid: "save" }
      )) { "Save" }

      span(data: { testid: "runs" }) { @runs.to_s }
    end
  end
end
