// The JS twin for the connect-time seed repro (issue #199). Registered under the
// "sums" reducer key. Returns ALL declared keys every pass — the two numeric
// outputs (total, half) AND the cross-root mirror (total_label) — so a single
// connect-time recompute paints every one from one result. This is the reducer
// shape from the issue: correctness is trivially all-keys-every-pass, so any
// blank output after connect is a client apply/seed bug, not a reducer bug.
import { setComputeReducer } from "phlex/reactive/compute"

export function registerComputeSeed() {
  setComputeReducer("sums", ({ a, b }) => {
    const total = Number(a) + Number(b)
    // total_ro (issue #204) mirrors total onto a DISABLED field — proves the
    // property write reaches a disabled output the value attribute never shows.
    return { total, half: total / 2, total_ro: total, total_label: `${total}` }
  })
}
