# frozen_string_literal: true

# Issue #179: NAMED-PREDICATE conditional confirm (the multi-field escape hatch).
# The save action warns ONLY when the end date precedes the start —
# confirm: { predicate: "end_before_start", message: } names a JS predicate
# registered at boot (confirm_predicate_registration.js) that the client runs
# over the collected { starts_at, ends_at }. A valid range submits silently; an
# inverted range prompts. `runs` bumps on save for the system spec's assertions.
class ScheduleConfirmComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :runs

  action :save, params: { starts_at: :string, ends_at: :string }

  def initialize(runs: 0)
    @runs = runs
  end

  def id = "schedule-confirm"

  def save(starts_at:, ends_at:)
    @runs += 1
  end

  def view_template
    # reactive_root already binds id + controller + token — do NOT also spread
    # reactive_attrs (that double-emits the token → a "token token" POST → 400).
    div(**reactive_root) do
      input(name: "starts_at", value: "2026-07-01", data: { testid: "starts-at" })
      input(name: "ends_at", value: "2026-07-10", data: { testid: "ends-at" })

      button(**mix(
        on(:save, confirm: { predicate: "end_before_start", message: "End precedes start — continue?" }),
        data: { testid: "save" }
      )) { "Save" }

      span(data: { testid: "runs" }) { @runs.to_s }
    end
  end
end
