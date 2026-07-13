// The JS twin for the issue #226 MULTI-BOX code entry — six single-character
// boxes behind ONE reducer. Every pass rebuilds the whole code by joining the
// boxes in order (so a paste into ANY box redistributes one digit per box),
// mirrors it into the hidden `code` field (what the intercepted submit
// carries), and emits $ops:
//
//   * incomplete after a user edit → focus the first EMPTY box. The $ops latch
//     is keyed on chain CONTENT, so each digit's DIFFERENT focus target fires
//     while an unchanged chain stays settled.
//   * complete → ops.submit() — the same rising-edge auto-commit as the
//     single-input flagship (otp_reducer.js).
import { setComputeReducer, ops } from "phlex/reactive/compute"

const BOXES = ["d1", "d2", "d3", "d4", "d5", "d6"]

export function registerSplitCode() {
  setComputeReducer("split_code", (boxes, { changed }) => {
    const digits = BOXES.map((n) => boxes[n]).join("").replace(/\D/g, "").slice(0, 6)
    const out = { code: digits }
    BOXES.forEach((name, i) => (out[name] = digits[i] ?? ""))
    const complete = digits.length === 6
    const advance = changed && digits.length > 0 ? ops.focus(`[name=d${digits.length + 1}]`) : null
    return { ...out, $ops: complete ? ops.submit() : advance }
  })
}
