// The JS twin of the Ruby PaymentSplit (spec/dummy/app/models/payment_split.rb).
// Registered under the "payment_split" reducer key so a NEW (unpersisted) order's
// reactive_compute recomputes the three-way split IN-BROWSER on input, with no
// round trip. A persisted order runs the identical math server-side. Keep the two
// in lockstep — that's the contract reactive_compute exists to enforce.
import { setComputeReducer } from "phlex/reactive/compute"

// values: { allowance, cash, leasing, total } as Numbers (blank → 0, handled by
// the controller). The controller passes the LIVE field values every time; we
// figure out which one the user just edited by comparing against the identity the
// reducer is called with... but since inputs are stateless here, we mirror the
// server contract: the edited field keeps its value, cash absorbs the remainder,
// and an over-total edit caps + zeros the peers.
//
// The demo edits `allowance` (the wired input), so `allowance` is authoritative
// and `cash`/`leasing` rebalance. This keeps the reducer tiny and matches
// PaymentSplit#rebalance(changed: :allowance).
export function registerPaymentSplit() {
  setComputeReducer("payment_split", ({ allowance, total }) => {
    // Mirrors PaymentSplit#rebalance(changed: :allowance): the edited allowance
    // keeps its value; cash absorbs the whole remainder; leasing zeros out. Cap
    // allowance at total (peers zero) when it exceeds the total.
    if (allowance >= total) return { allowance: total, cash: 0, leasing: 0 }
    return { allowance, cash: total - allowance, leasing: 0 }
  })
}
