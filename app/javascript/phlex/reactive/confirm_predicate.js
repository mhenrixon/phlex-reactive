// The client-side confirm-predicate registry — the multi-field escape hatch for
// conditional confirmation (issue #179).
//
// confirm: { when: { total: 0 }, message: } handles the single-field 80% case
// declaratively (the reactive_show conditions language), with NO JS. But some
// soft-validation is multi-field — "warn if the end date precedes the start",
// "warn if two related totals disagree" — which a single field=value condition
// can't express. This registry is the seam for that logic: name a pure function
// with `confirm: { predicate: "name", message: }` (Ruby) and register it here.
//
// The seam mirrors compute.js (setComputeReducer) and confirm.js: a settable
// registry with a lookup the controller calls. Register once at boot:
//
//   import { setConfirmPredicate } from "phlex/reactive/confirm_predicate"
//   setConfirmPredicate("end_before_start", ({ starts_at, ends_at }) =>
//     ends_at !== "" && ends_at < starts_at)
//
// The predicate's signature is (fields) => boolean:
//
//   fields — a plain object of { name: value } over the trigger root's collected
//            controls (the SAME snapshot reactive_compute reads — #collectFields).
//            Values are the raw control values (strings; a checkbox is a boolean).
//
// It returns truthy to WARN (the confirm dialog fires with the declared message)
// or falsy to PROCEED with no dialog. The predicate is soft-validation UX, NOT
// authorization: a user can bypass it (devtools, an unregistered name) and the
// action still hits the endpoint's real authorize/default-deny — never let a
// predicate stand in for a server-side check.
//
// A missing predicate (name never registered) makes the gate a NO-OP: the
// controller proceeds WITHOUT a dialog and warns, exactly like compute.js's
// unknown-reducer posture — a stale/typo'd name must not break the page or
// (worse) block a legitimate action behind a dialog that can never resolve.

const predicates = new Map()

// Register (or replace) the predicate for `key`. `fn` is
// (fields: Record<string, unknown>) => boolean — truthy warns, falsy proceeds.
export function setConfirmPredicate(key, fn) {
  predicates.set(key, fn)
}

// Look up a registered predicate; undefined when none — the controller then
// proceeds without a dialog (and warns) rather than throwing or blocking.
export function confirmPredicate(key) {
  return predicates.get(key)
}

// Test seam: clear the registry so a predicate registered in one test can't leak.
export function __resetConfirmPredicateRegistryForTest() {
  predicates.clear()
}
