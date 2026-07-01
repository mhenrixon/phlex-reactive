// The client-side compute (data-binding) registry — the "instant" half of the
// new/unpersisted-record UX.
//
// A record-backed reactive component round-trips every change to the server
// (the signed identity re-finds the record; the server re-renders). A NEW,
// unpersisted record has no such server truth to re-render against on every
// keystroke — the classic answer is a bespoke Stimulus controller doing the math
// in the browser (carlqvist's new_order_controller.js). This registry lets that
// math be a DECLARED part of the component instead: `reactive_compute :name,
// inputs:, outputs:` (Ruby) names a reducer registered here, and the generic
// reactive controller runs it on `input` — writing the outputs with NO round
// trip. When the component ALSO carries on(...) (a persisted record, or a draft
// you sync), the debounced POST reconciles from the authoritative server reply.
//
// The seam mirrors confirm.js: a settable registry with a lookup the controller
// calls. Register once at boot:
//
//   import { setComputeReducer } from "phlex/reactive/compute"
//   setComputeReducer("payment_split", ({ allowance, cash, leasing, total }) => ({
//     allowance, leasing, cash: total - allowance - leasing,
//   }))
//
// The reducer receives a plain object of { inputName: Number } and returns a
// plain object of { outputName: value } — only the outputs it names are written,
// so it can leave the edited field (and its caret) untouched. Returning the SAME
// value it read is a no-op write; the controller still fires `input` on any field
// it sets so a chained summary repaints, matching the server's set_value +
// dispatch("input") contract.

const reducers = new Map()

// Register (or replace) the reducer for `key`. `fn` is
// (values: Record<string, number>) => Record<string, unknown>.
export function setComputeReducer(key, fn) {
  reducers.set(key, fn)
}

// Look up a registered reducer; undefined when none — the controller then makes
// #recompute a no-op rather than throwing (a missing reducer must not break the
// page; it just means no client-side binding for that root).
export function computeReducer(key) {
  return reducers.get(key)
}

// Test seam: clear the registry so a reducer registered in one test can't leak.
export function __resetComputeRegistryForTest() {
  reducers.clear()
}
