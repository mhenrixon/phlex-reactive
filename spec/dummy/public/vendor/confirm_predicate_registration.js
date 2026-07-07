// Registers the demo's conditional-confirm predicate (issue #179). The
// ScheduleConfirmComponent gates its save behind confirm: { predicate:
// "end_before_start", … } — a multi-field soft-validation the single-field
// declarative form can't express. This is the JS escape hatch, the twin of the
// compute-reducer registration.
import { setConfirmPredicate } from "phlex/reactive/confirm_predicate"

export function registerConfirmPredicates() {
  // Warn (return truthy) when the end date precedes the start — collected fields
  // are { starts_at, ends_at } (raw string values). Blank end never warns.
  setConfirmPredicate("end_before_start", ({ starts_at, ends_at }) =>
    ends_at !== "" && starts_at !== "" && ends_at < starts_at
  )
}
