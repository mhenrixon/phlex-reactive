import { Controller } from "@hotwired/stimulus"
import {
  enableLatencySim,
  disableLatencySim,
  LATENCY_KEY,
} from "phlex/reactive/reactive_controller"

// A docs-owned latency toggle. The docs site is deliberately a demo site, so we
// import the simulator's named exports DIRECTLY from the gem's client runtime
// (auto-pinned by the engine) rather than gating on the app-authored
// `<meta name="phlex-reactive-env" content="development">` console handle — that
// gate exists to keep window.PhlexReactive off a real production page, which is
// the opposite of what a live demo site wants. No gem change; no env spoofing.
//
// State lives in sessionStorage under LATENCY_KEY (read live per action by the
// reactive controller), so flipping the checkbox takes effect on the very next
// click with no reload. We reflect the current key value on connect so the
// control survives a Turbo navigation.
export default class extends Controller {
  static values = { ms: { type: Number, default: 400 } }

  connect() {
    this.element.checked = this.#active()
  }

  toggle() {
    if (this.element.checked) {
      enableLatencySim(this.msValue)
    } else {
      disableLatencySim()
    }
  }

  #active() {
    if (typeof sessionStorage === "undefined") return false
    const ms = Number(sessionStorage.getItem(LATENCY_KEY))
    return Number.isFinite(ms) && ms > 0
  }
}
