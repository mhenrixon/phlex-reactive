// The JS twin for the issue #226 $ops flagship — a one-time-code field that
// normalizes on every input (strip non-digits, cap at 6) and, once complete,
// emits the reserved $ops output to submit its own form. The component root IS
// the form, so ops.submit() (default target @root) requestSubmits it directly;
// the real submit event fires and on(:verify, event: "submit") intercepts it
// into ONE signed action POST. Rising-edge: a 7th keystroke (capped back to
// the same complete value) never re-fires; going incomplete re-arms.
import { setComputeReducer, ops } from "phlex/reactive/compute"

export function registerOtp() {
  setComputeReducer("otp", ({ code }) => {
    const digits = code.replace(/\D/g, "").slice(0, 6)
    return { code: digits, $ops: digits.length === 6 ? ops.submit() : null }
  })
}
