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
// The reducer's signature is (values, meta):
//
//   values — a plain object of { inputName: Number } over the declared inputs
//   meta   — { changed }: the name (string) of the declared input the
//            triggering event edited, or null (a direct recompute() call, or a
//            target this root doesn't own / didn't declare as an input).
//
// It returns a plain object of { outputName: value } — only the outputs it
// names are written, so it can leave the edited field (and its caret)
// untouched. A one-argument reducer keeps working unchanged (it just ignores
// meta). `changed` is what makes a MULTI-WAY / MUTUAL rebalance expressible as
// one reducer (issue #75) — branch on which field the user edited:
//
//   setComputeReducer("three_way_split", ({ field_a, field_b, field_c, total }, { changed }) => {
//     if (changed === "field_c") return { field_a: total - field_c - field_b }
//     return { field_c: total - field_a - field_b }
//   })
//
// Output writes are CHANGE-GUARDED: the controller writes a field and
// dispatches a bubbling `input` event on it ONLY when the new value differs
// from the field's current value (real browsers never fire `input` on a
// programmatic .value write, so the controller dispatches explicitly — that's
// what drives a chained summary repaint, matching the server's set_value +
// dispatch("input") contract). Returning the SAME value a field already holds
// is skipped entirely — no write, no event — which is why a reducer with
// overlapping inputs/outputs (like payment_split above) settles instead of
// re-entering itself forever.
//
// CONVERGENCE REQUIREMENT: because an output write dispatches a REAL input
// event (issue #76), recompute re-enters with changed = that OUTPUT field's
// name (when it's also a declared input). A branching reducer must therefore
// be convergent: the re-entrant pass must compute values EQUAL to what the
// first pass already wrote to the DOM, so the change guard settles the chain.
// The three_way_split above is: after `changed === "field_a"` writes field_c,
// the re-entrant `changed === "field_c"` pass derives field_a back to the
// value it already holds — no write, no event, settled in one bounce.

const reducers = new Map()

// Register (or replace) the reducer for `key`. `fn` is
// (values: Record<string, number>, meta: { changed: string | null })
//   => Record<string, unknown>.
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
