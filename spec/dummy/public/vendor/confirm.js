// The overridable confirmation resolver behind `on(:action, confirm: "…")`
// (issue #55, follow-up to #52).
//
// The reactive controller preempts the click event (its own preventDefault +
// POST), so Hotwire's `data-turbo-confirm` — which routes through
// `Turbo.config.forms.confirm` — never runs for a reactive trigger. That made
// the reactive path the ONE interaction a Hotwire app couldn't theme: every
// confirmable reactive action showed the unstyled native window.confirm chrome.
//
// This module is the seam. `dispatch` resolves the confirm message through
// `confirmResolver`, which defaults to a Promise-wrapped window.confirm (so the
// 0.4.5 behavior is byte-for-byte unchanged when nothing is configured: sync,
// no dependency, screen-reader friendly). An app reuses its themed dialog with
// one line at boot:
//
//   import { setConfirmResolver } from "phlex/reactive/confirm"
//   setConfirmResolver((message) => window.Turbo.config.forms.confirm(message))
//
// The resolver may be sync or async — the controller awaits it via
// Promise.resolve, so a bare boolean and a Promise<boolean> both work. It must
// resolve truthy to proceed; a falsy resolve (or a rejection) cancels the
// action — exactly like declining the native prompt.

// The default: wrap the synchronous native confirm in a Promise so the call
// site can always `await` it. Read window lazily (per call), not at module load
// — under SSR / test the global may not exist yet when this module is imported.
export let confirmResolver = (message) =>
  Promise.resolve(typeof window !== "undefined" ? window.confirm(message) : true)

// Override the resolver. Pass a function `(message) => boolean | Promise<boolean>`.
// Truthy resolves the action through; falsy (or a rejected Promise) cancels it.
export function setConfirmResolver(fn) {
  confirmResolver = fn
}
