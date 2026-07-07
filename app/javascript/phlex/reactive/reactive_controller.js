import { Controller } from "@hotwired/stimulus"
// Import the BARE specifier the engine already pins (phlex/reactive/confirm),
// NOT a relative "./confirm.js" (issue #57). Under importmap-rails + Propshaft
// the controller is served at its DIGESTED url; a relative sibling import is
// left untouched (Propshaft rewrites only RAILS_ASSET_URL(...), and the import
// map resolves ONLY bare specifiers), so "./confirm.js" resolves against the
// digested controller url → an undigested /assets/.../confirm.js that 404s, and
// the throwing import takes down every Stimulus controller on the page. The
// bare specifier resolves to the digested asset through the import map, and
// bundlers/bun resolve it the same way they already resolve
// "phlex/reactive/reactive_controller" (see tsconfig.json paths for the tests).
import { confirmResolver } from "phlex/reactive/confirm"
// Client-side computes (data bindings): the reducer registry behind
// reactive_compute. Bare specifier for the same import-map reason as confirm.
import { computeReducer } from "phlex/reactive/compute"

// The ONE generic controller behind every reactive Phlex component. It
// replaces the per-feature Stimulus controllers you'd otherwise hand-write
// for interactive components. A component declares its actions in Ruby (via
// Phlex::Reactive::Component); this controller binds DOM events to a single
// HTTP round trip and lets Turbo apply the re-rendered component back in
// (replace by default; method="morph" — Response.morph — preserves focus).
//
// Wire format (client -> server), POST <action path>, turbo-stream Accept:
//   { token: "<signed identity>", act: "<action>", params: {...} }   (JSON)
// (`act`, not `action`: `action` is a reserved Rails routing param.)
// The token is a MessageVerifier-signed { component, gid } — NO state is sent.
// When the root holds a chosen <input type="file">, the SAME payload is sent as
// multipart FormData instead (token/act flat, params bracketed, files appended)
// so an upload reaches the action (issue #34) — only the encoding differs.
// The response is a <turbo-stream> that replaces the component by its id.
//
// Server -> client live updates use the SAME element id, pushed over the
// stream transport (pgbus SSE / Action Cable) via the Streamable
// .broadcast_* methods — so a click and a background broadcast converge on
// one re-render unit.
//
// Custom turbo-stream action: the server tells the actor to full-navigate
// (e.g. the record's slug changed and the current URL is now dead). It rides a
// 200 turbo-stream — NOT an HTTP 3xx — so it never trips the response.redirected
// bail below (which still correctly catches real auth/CSRF redirects). Registered
// once on the Turbo global (no @hotwired/turbo import — the gem uses window.Turbo
// everywhere, and a named import is unreliable under importmap/esbuild).
export function registerReactiveVisit() {
  const actions = window.Turbo?.StreamActions
  if (!actions || actions["reactive:visit"]) return
  actions["reactive:visit"] = function () {
    const url = this.getAttribute("data-url")
    if (url) window.Turbo.visit(url, { action: "advance" })
  }
}

// Custom turbo-stream action: a TOKEN-ONLY refresh (issue #30). A partial
// update (Response.streams / reply.streams) re-renders only PART of a component
// — so there's no full-self replace to carry the next signed token. The server
// instead emits `<turbo-stream action="reactive:token" target="<id>"
// data-reactive-token-value="<fresh>">`. #perform's #extractToken already reads
// the token out of the response body for the NEXT queued request; this handler
// keeps the DOM in sync too, writing the attribute onto the root element so the
// `tokenValue` fallback stays fresh. It's a pure attribute set — no node is
// replaced — so a focused <input> + caret survive (the whole point: update a
// total cell without tearing down the field the user is typing in).
export function registerReactiveToken() {
  const actions = window.Turbo?.StreamActions
  if (!actions || actions["reactive:token"]) return
  actions["reactive:token"] = function () {
    const token = this.getAttribute("data-reactive-token-value")
    const target = this.getAttribute("target")
    if (!token || !target) return
    const el = document.getElementById(target)
    // Stimulus reads the token via the `token` value -> data-reactive-token-value.
    if (el) el.setAttribute("data-reactive-token-value", token)
  }
}

// Custom turbo-stream action: SERVER-PUSHED client DOM ops (issue #97). The
// server-side sibling of on_client's runOps — a reply (reply.<verb>.js(ops)) or
// a broadcast (Streamable.broadcast_js_to) emits
//
//   <turbo-stream action="reactive:js" target="<optional root id>"
//                 data-reactive-ops="[[op, args], ...]"></turbo-stream>
//
// and Turbo invokes this handler with `this` bound to that <turbo-stream>
// element. It runs the ops through the SAME frozen CLIENT_OPS whitelist as
// runOps (client-side default-deny — an unknown op warns + is skipped), so a
// forged/stale ops attr can never break the page or execute anything off the
// vocabulary. NO token, NO fetch — a pure local DOM mutation.
//
// `target` (optional, an element id) scopes op resolution to that root: "@root"
// resolves to the target element itself and a selector resolves WITHIN it.
// Without a target, ops resolve document-wide (a broadcast op like
// add_class("#bell", ...) that isn't anchored to one component). The op stream
// is emitted AFTER all render streams in the reply (the endpoint appends it
// last), so focus("[name=next]") sees the freshly morphed DOM — Turbo applies
// streams in document order.
export function registerReactiveJs() {
  const actions = window.Turbo?.StreamActions
  if (!actions || actions["reactive:js"]) return
  actions["reactive:js"] = function () {
    const list = parseOps(this.getAttribute("data-reactive-ops"))
    if (!list.length) return
    const targetId = this.getAttribute("target")
    // With a target: scope to that element (missing → no-op). Without: document.
    const root = targetId ? document.getElementById(targetId) : null
    if (targetId && !root) return
    applyOps(list, (args) => streamOpTargets(args, root))
  }
}

// --- Deferred reply segments (issue #165) ----------------------------------
// The client half of reply.defer: the server's reply carries a
// `<turbo-stream action="reactive:defer" target="<id>">` directive and the
// real render reaches the SAME actor later — via a parallel fetch (pull) or a
// pgbus one-shot stream (push). Everything here is MODULE-level, deliberately
// OFF the per-controller request queue: the whole point is that the expensive
// segment never blocks the actor's next action.
//
// Supersession is the correctness core: pendingDefers keys one in-flight
// delivery per target id. A newer directive for the same target aborts the
// older fetch (or removes the older stream source), and an arrival applies
// ONLY while its entry is still current — so a fast typist's debounced
// keystrokes can never paint stale totals over fresh ones.
const pendingDefers = new Map()

// Test seam: clear the module-level registry between unit tests. Also resets
// the one-shot settle-listener guard so a test's fresh document re-registers
// the turbo:before-stream-render settler.
export function resetReactiveDefers() {
  pendingDefers.clear()
  deferStreamSettleRegistered = false
}

// Test seam: the `via` of a target's pending defer entry (or undefined) — lets
// tests assert an entry was SETTLED (dropped) on arrival without exposing the
// Map. Not used by the runtime.
export function pendingDeferVia(targetId) {
  return pendingDefers.get(targetId)?.via
}

let deferStreamSettleRegistered = false

export function registerReactiveDefer() {
  const actions = window.Turbo?.StreamActions
  if (!actions || actions["reactive:defer"]) return
  actions["reactive:defer"] = function () {
    const target = this.getAttribute("target")
    if (!target) return
    if (this.getAttribute("data-reactive-defer-via") === "stream") {
      startStreamDefer(target, this)
      return
    }
    const token = this.getAttribute("data-reactive-defer-token")
    if (!token) return
    startFetchDefer(target, token)
  }

  // Settle a STREAM-lane pendingDefers entry when its arrival lands: the job's
  // broadcast is a turbo-stream that replaces the target (and removes the
  // source). A document-level turbo:before-stream-render hook drops the Map
  // entry for a stream target the moment a stream renders against it — so the
  // entry never outlives the delivery (the fetch lane settles inline; the
  // stream lane's arrival is a broadcast this controller doesn't await, so it
  // needs this hook). Registered once; a no-op without document.
  if (!deferStreamSettleRegistered && typeof document !== "undefined" && document.addEventListener) {
    deferStreamSettleRegistered = true
    document.addEventListener("turbo:before-stream-render", settleStreamDeferOnRender)
  }
}

// Drop a stream-lane pendingDefers entry when a turbo-stream renders against
// its target id (the job's replace) OR removes its source element. Keyed by the
// stream's target so an unrelated stream never settles a defer. Pure Map
// cleanup — the DOM apply is Turbo's; this only releases our bookkeeping.
function settleStreamDeferOnRender(event) {
  const streamEl = event.target
  const target = streamEl?.getAttribute?.("target")
  if (!target) return
  // The arrival replaces #<target>; the source removal targets
  // reactive-defer-src-<target>. Either signals the stream delivered.
  const targetId = target.startsWith("reactive-defer-src-")
    ? target.slice("reactive-defer-src-".length)
    : target
  const entry = pendingDefers.get(targetId)
  if (entry?.via === "stream") pendingDefers.delete(targetId)
}

// The pull lane: mark the target pending and POST the signed defer token to
// the defer endpoint, in parallel with everything else the page is doing.
function startFetchDefer(targetId, token) {
  const el = document.getElementById(targetId)
  if (!el) {
    console.warn(`[phlex-reactive] reactive:defer target #${targetId} is not on the page — skipped`)
    return
  }
  supersedeDefer(targetId)
  markDeferPending(el)
  const entry = { via: "fetch", abort: new AbortController(), timedOut: false }
  pendingDefers.set(targetId, entry)
  performDeferFetch(targetId, entry, token)
}

// The push lane: subscribe a <pgbus-stream-source> to the server-signed
// one-shot stream. Arrival + teardown need no client logic — the job's
// broadcast carries the replace AND a remove of this source element (its
// disconnectedCallback closes the SSE connection). since-id=0 on a fresh key
// replays a broadcast that beat the subscription (the durable-lane guarantee).
function startStreamDefer(targetId, directive) {
  const el = document.getElementById(targetId)
  if (!el) {
    console.warn(`[phlex-reactive] reactive:defer target #${targetId} is not on the page — skipped`)
    return
  }
  const src = directive.getAttribute("data-reactive-defer-src")
  if (!src) return
  if (!globalThis.customElements?.get?.("pgbus-stream-source")) {
    // The server chose push on server-side capability, but this page has no
    // pgbus client. Degrade to the fetch lane using the fallback token the push
    // directive carries — rather than dead-end the shimmer. No token (an app on
    // a bespoke transport) is a loud no-op.
    const fallbackToken = directive.getAttribute("data-reactive-defer-token")
    if (fallbackToken) {
      startFetchDefer(targetId, fallbackToken)
      return
    }
    console.error(
      "[phlex-reactive] reactive:defer via=stream but <pgbus-stream-source> is not registered " +
        "and no fallback token was provided — is the pgbus client loaded on this page?",
    )
    return
  }
  supersedeDefer(targetId)
  markDeferPending(el)
  const source = document.createElement("pgbus-stream-source")
  // Deterministic id: the JOB's broadcast removes it by this exact id — the
  // subscription tears itself down with the payload it delivered.
  source.id = deferSourceId(targetId)
  source.setAttribute("src", src)
  source.setAttribute("since-id", directive.getAttribute("data-reactive-defer-since-id") ?? "0")
  source.setAttribute("hidden", "")
  document.body.appendChild(source)
  // Record only { via } — NOT a strong ref to the source element. The job's
  // broadcast removes the source by its deterministic id (its
  // disconnectedCallback closes the SSE), so holding srcEl here would pin the
  // detached node in this module-level Map forever (a leak). Supersession
  // re-finds the element by id instead. The entry is dropped on
  // supersession or when the arriving broadcast replaces the target (a
  // turbo:before-stream-render hook, below).
  pendingDefers.set(targetId, { via: "stream" })
}

// The deterministic id of a target's one-shot <pgbus-stream-source>.
function deferSourceId(targetId) {
  return `reactive-defer-src-${targetId}`
}

async function performDeferFetch(targetId, entry, token) {
  // Bound the wait like the action fetch (issue #101) — a hung defer must not
  // shimmer forever. A manual timer (not AbortSignal.timeout) so the catch can
  // tell a TIMEOUT (fail loudly) from a SUPERSEDED abort (stay silent).
  const timer = setTimeout(() => {
    entry.timedOut = true
    entry.abort.abort()
  }, deferTimeoutMs())

  // The timeout is cleared ONLY after the body is fully read (below), not the
  // moment headers arrive — a server that streams headers then stalls the body
  // must still abort, or the shimmer hangs forever (the abort signal covers the
  // whole fetch + body read, mirroring #perform's AbortSignal.timeout).
  let response
  try {
    response = await fetch(deferPath(), {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "Content-Type": "application/json",
        "X-CSRF-Token": deferCsrfToken(),
      },
      body: JSON.stringify({ token }),
      credentials: "same-origin",
      signal: entry.abort.signal,
    })
  } catch (error) {
    clearTimeout(timer)
    if (pendingDefers.get(targetId) !== entry) return // superseded — silent
    console.error("[phlex-reactive] deferred render failed", error)
    failDefer(targetId, token)
    return
  }
  if (pendingDefers.get(targetId) !== entry) {
    clearTimeout(timer)
    return // superseded mid-flight
  }

  if (response.status === 204) {
    clearTimeout(timer)
    // render? false — keep the current content, just clear the pending state.
    settleDefer(targetId)
    return
  }
  if (!response.ok) {
    clearTimeout(timer)
    console.error(`[phlex-reactive] deferred render failed: HTTP ${response.status}`)
    failDefer(targetId, token, response.status)
    return
  }

  let html
  try {
    html = await response.text()
  } catch (error) {
    clearTimeout(timer)
    if (pendingDefers.get(targetId) !== entry) return
    console.error("[phlex-reactive] deferred render failed reading the body", error)
    failDefer(targetId, token)
    return
  }
  clearTimeout(timer)
  if (pendingDefers.get(targetId) !== entry) return // superseded during read

  settleDefer(targetId)
  // A normal replace/morph of the target — the fresh root carries no pending
  // markers and a fresh action token, so the component lands interactive.
  window.Turbo.renderStreamMessage(html)
}

// Abort/unsubscribe whatever delivery is in flight for this target. The
// deleted entry makes every late arrival fail its identity check — stale
// content can never paint.
function supersedeDefer(targetId) {
  const existing = pendingDefers.get(targetId)
  if (!existing) return
  pendingDefers.delete(targetId)
  if (existing.via === "fetch") existing.abort.abort()
  // Stream lane: re-find the old source by its deterministic id and remove it
  // (unsubscribe) — we deliberately don't hold a strong ref to the detached
  // node. Its disconnectedCallback closes the SSE.
  else document.getElementById(deferSourceId(targetId))?.remove?.()
}

function markDeferPending(el) {
  el.setAttribute("data-reactive-defer-pending", "true")
  el.setAttribute("aria-busy", "true")
}

function clearDeferPending(el) {
  el.removeAttribute("data-reactive-defer-pending")
  el.removeAttribute("aria-busy")
}

// Success/204: drop the registry entry, clear pending, and clear any prior
// defer failure marker (recovery resets error-driven CSS, issue #100 style).
function settleDefer(targetId) {
  pendingDefers.delete(targetId)
  const el = document.getElementById(targetId)
  if (!el) return
  clearDeferPending(el)
  el.removeAttribute("data-reactive-error")
}

// Failure: clear pending (the shimmer must not lie), mark the root
// (data-reactive-error="defer" — style it in pure CSS), and emit a bubbling
// reactive:error whose retry() re-enters the defer fetch with the SAME token
// (still valid inside the TTL; an expired token 400s into this same path).
function failDefer(targetId, token, status) {
  pendingDefers.delete(targetId)
  const el = document.getElementById(targetId)
  if (!el) return
  clearDeferPending(el)
  el.setAttribute("data-reactive-error", "defer")
  const retry = () => {
    const fresh = document.getElementById(targetId)
    if (!fresh) {
      console.warn("[phlex-reactive] defer retry() ignored — the target left the DOM")
      return
    }
    fresh.removeAttribute("data-reactive-error")
    startFetchDefer(targetId, token)
  }
  el.dispatchEvent(
    new CustomEvent("reactive:error", {
      bubbles: true,
      composed: true,
      detail: { kind: "defer", target: targetId, status, retry },
    }),
  )
}

function deferPath() {
  return document.querySelector('meta[name="phlex-reactive-defer-path"]')?.content || "/reactive/defer"
}

// CSRF is read LIVE per request (Rails can rotate it) — same contract as the
// controller's #csrfToken.
function deferCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
}

// Same page-stable meta + default as the controller's #timeoutMs (issue #101),
// parsed defensively so a typo'd meta can never disable the bound.
function deferTimeoutMs() {
  const raw = document.querySelector('meta[name="phlex-reactive-timeout"]')?.content
  const ms = Number(raw)
  return Number.isFinite(ms) && ms > 0 ? ms : 30000
}

// Document-level self-dismissing flashes (issue #100). A flash rendered with
// dismiss_after: carries data-reactive-dismiss-after="<ms>"; after the timeout
// it removes itself. This is deliberately NOT a Stimulus controller — the flash
// container is a plain host-app div (Response#flash appends into it) with no
// controller attached, so nothing would honor the attr. A document-level scan
// on turbo:before-stream-render (which fires for EVERY <turbo-stream> render —
// a reply AND a broadcast) schedules removal for any newly-arrived dismissing
// flash. Each is marked data-reactive-dismiss-scheduled so re-scans (a later
// stream render) never double-schedule the same node. Registered once; the
// guard flag makes a second call a no-op (bun imports the module once per run).
let dismissRegistered = false
export function registerReactiveDismiss() {
  if (dismissRegistered) return
  if (typeof document === "undefined" || !document.addEventListener) return
  dismissRegistered = true
  // turbo:before-stream-render fires BEFORE the stream is applied — and Turbo
  // then does `await nextRepaint(); await event.detail.render(this)`, so a bare
  // setTimeout(0) can run BEFORE the node is inserted (observed under Falcon).
  // WRAP event.detail.render instead: run Turbo's own render, then scan once it
  // has resolved — timing-independent and correct on every server. The event
  // fires for EVERY <turbo-stream> (a reply AND a broadcast), so both delivery
  // paths self-clean. detail.render may be absent on exotic streams — guard it.
  document.addEventListener("turbo:before-stream-render", wrapStreamRenderForDismiss)
}

// Chain the dismissing-flash scan after Turbo's own stream render resolves, so
// the scan sees the freshly-inserted node. Idempotent per event (marks
// detail.render as already-wrapped) and defensive if detail/render is missing.
function wrapStreamRenderForDismiss(event) {
  const detail = event.detail
  const original = detail?.render
  if (typeof original !== "function" || original.__reactiveDismissWrapped) {
    // No render to wrap (or already wrapped) — fall back to a post-repaint scan.
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(scheduleReactiveDismissals)
    else setTimeout(scheduleReactiveDismissals, 0)
    return
  }
  const wrapped = async (streamElement) => {
    await original(streamElement)
    scheduleReactiveDismissals()
  }
  wrapped.__reactiveDismissWrapped = true
  detail.render = wrapped
}

// Scan for un-scheduled dismissing flashes and schedule each one's removal.
// Kept a module function so the scan logic is testable and re-run on every
// stream render.
function scheduleReactiveDismissals() {
  const flashes = document.querySelectorAll("[data-reactive-dismiss-after]")
  for (const el of flashes) {
    if (el.hasAttribute("data-reactive-dismiss-scheduled")) continue
    const ms = Number(el.getAttribute("data-reactive-dismiss-after"))
    if (!Number.isFinite(ms) || ms <= 0) continue
    el.setAttribute("data-reactive-dismiss-scheduled", "")
    setTimeout(() => el.remove(), ms)
  }
}

// Test seam: reset the one-time registration guard so a fresh document stub in
// the next test registers its own listener (bun runs all specs in one process).
export function __resetReactiveDismissForTest() {
  dismissRegistered = false
}

// Offline CSS hook (issue #101). Mirror data-reactive-offline on
// document.documentElement from navigator.onLine, kept in sync by the window
// online/offline events — so an app can dim a save button or show a banner with
// PURE CSS and zero JS ([data-reactive-offline] .save { pointer-events: none }).
// Guarded on window (needed for addEventListener AND navigator) so importing the
// module in a non-browser (bun test) context is a no-op, and registered once
// (the online/offline listeners are NOT {once}, so a second registerReactiveActions
// call must not stack duplicates) — mirroring the dismiss guard + reset seam.
let offlineRegistered = false
export function registerReactiveOffline() {
  if (offlineRegistered) return
  if (typeof window === "undefined" || typeof document === "undefined") return
  if (typeof window.addEventListener !== "function") return
  offlineRegistered = true
  // toggleAttribute(name, force) writes data-reactive-offline="" (a bare boolean
  // attr the [data-reactive-offline] selector matches) or removes it — never the
  // "true" string. navigator.onLine === false is the reliable direction (a false
  // "online" is spec-permitted but rare, and this is only a presentational hook —
  // the authoritative offline signal is the #perform gate, not this attribute).
  // Fully defensive: a missing documentElement/toggleAttribute/navigator degrades
  // to a no-op — a presentational hook must NEVER throw during bootstrap.
  const sync = () => {
    const root = document.documentElement
    if (typeof root?.toggleAttribute !== "function") return
    root.toggleAttribute("data-reactive-offline", globalThis.navigator?.onLine === false)
  }
  sync() // seed synchronously so first paint is correct
  window.addEventListener("online", sync)
  window.addEventListener("offline", sync)
}

export function __resetReactiveOfflineForTest() {
  offlineRegistered = false
}

// Latency simulator dev aid (issue #102). On localhost the click→morph round
// trip is ~5ms, so the pending/loading/optimistic affordances (aria-busy,
// disable_with, busy_on, optimistic hints) flash by too fast to see while
// developing or demoing them — the reason LiveView ships enableLatencySim(ms).
//
// enableLatencySim(ms) persists the delay to sessionStorage (session-scoped, so
// it clears when the tab closes — never a config you forget you left on);
// #perform reads it right before the fetch and awaits setTimeout(ms), stretching
// the already-set busy window to something visible. disableLatencySim() clears
// it. NAMED exports (the setConfirmResolver precedent) — but importmap module
// exports are unreachable from the browser console, so registerReactiveActions
// ALSO attaches these to window.PhlexReactive, and ONLY when the app opts in with
// <meta name="phlex-reactive-env" content="development"> (see #attachLatencyHandle).
export const LATENCY_KEY = "phlex-reactive:latency"

// One-time "sim active" banner guard (module-level, mirroring offlineRegistered):
// #maybeSimulateLatency warns ONCE while the sim is on, not once per request.
let latencyBannerShown = false

export function enableLatencySim(ms) {
  if (typeof sessionStorage === "undefined") return
  sessionStorage.setItem(LATENCY_KEY, String(ms))
}

export function disableLatencySim() {
  if (typeof sessionStorage === "undefined") return
  sessionStorage.removeItem(LATENCY_KEY)
  // Re-arm the one-time "sim active" banner: turning the sim OFF is the lifecycle
  // boundary, so a later enableLatencySim() in the same session re-announces that
  // the sim is on (otherwise the guard would stay set across an off→on cycle and
  // swallow the banner). Matches the __resetReactiveLatencyForTest seam.
  latencyBannerShown = false
}

// The dev gate. importmap module exports aren't reachable from the DevTools
// console, so we expose the two functions on a window handle — but ONLY when the
// app authored <meta name="phlex-reactive-env" content="development">. There is
// NO engine-emitted meta (the engine can't inject into the host layout); the
// install generator ships the snippet commented. Without the meta: no global
// handle at all, and #perform short-circuits on the null sessionStorage read —
// zero production surface. The `?.content` chain is fully defensive (a stubbed
// document with no querySelector, a missing meta) so bootstrap never throws.
function attachLatencyHandle() {
  if (typeof window === "undefined" || typeof document === "undefined") return
  const env = document.querySelector?.('meta[name="phlex-reactive-env"]')?.content
  if (env !== "development") return
  window.PhlexReactive = { enableLatencySim, disableLatencySim }
}

// Test seam: forget the one-time active-sim banner so the next test re-warns.
export function __resetReactiveLatencyForTest() {
  latencyBannerShown = false
}

export function registerReactiveActions() {
  registerReactiveVisit()
  registerReactiveToken()
  registerReactiveJs()
  registerReactiveDefer()
  registerReactiveDismiss()
  registerReactiveOffline()
  attachLatencyHandle()
}

// Escape a DOM id for safe interpolation into a RegExp (an id can legally contain
// regex metacharacters like `.`/`:` — e.g. an `escape:`-namespaced or dotted id).
// Used by #extractToken to match the stream that re-renders THIS element by id.
export function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

if (typeof window !== "undefined") {
  if (window.Turbo) registerReactiveActions()
  else document.addEventListener("turbo:load", registerReactiveActions, { once: true })
}

// --- Registration guard (issue #26 part 2) -------------------------------
// In a `lazyLoadControllersFrom("controllers", application)` app, only
// controllers under app/javascript/controllers/ are registered. This module
// lives outside that dir, so importing it isn't enough — `data-controller=
// "reactive"` does NOTHING until the host runs application.register("reactive",
// ...). The failure is silent: components render, but no action ever fires.
//
// We can't warn from connect() in that case (connect never runs). Instead, once
// the page is ready, if reactive elements exist but no controller has connected,
// the controller wasn't registered — so we warn, pointing at the fix.
let reactiveConnected = false

export function checkReactiveRegistration() {
  if (reactiveConnected) return
  if (typeof document === "undefined") return
  const els = document.querySelectorAll('[data-controller~="reactive"]')
  if (!els || els.length === 0) return
  console.warn(
    "[phlex-reactive] found " + els.length + ' element(s) with data-controller="reactive" ' +
      "but the reactive controller never connected. It is loaded but not registered — " +
      'add `application.register("reactive", ReactiveController)` (importmap) or import it ' +
      "into app/javascript/controllers/ for lazyLoadControllersFrom apps. See the README."
  )
}

// Test seams (no-ops in production usage).
export function __resetReactiveRegistrationForTest() {
  reactiveConnected = false
}
export function __markReactiveConnectedForTest() {
  reactiveConnected = true
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  // Defer past initial controller connection (a microtask/tick after ready).
  const scheduleCheck = () => setTimeout(checkReactiveRegistration, 0)
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scheduleCheck, { once: true })
  } else {
    scheduleCheck()
  }
}

// The interpret-time attribute-name allowlist (issue #96) — the SECOND half of
// the two-sided default-deny. The Ruby builder already refuses these at build
// time; this guards a hand-built / forged ops attr from bypassing it. Refused:
// event handlers (on*, XSS), URL-bearing names (a javascript: navigation
// surface), and style (CSS injection). Case-insensitive, mirroring js.rb.
const REFUSED_ATTR_URL = new Set(["href", "src", "srcdoc", "action", "formaction", "xlink:href", "style"])
function attrRefused(name) {
  const lower = String(name).toLowerCase()
  return lower.startsWith("on") || REFUSED_ATTR_URL.has(lower)
}

// Run an animated visibility change (issue #96 `transition:`). `flip` performs
// the actual hidden-flag change; `[during, from, to]` are class lists applied
// AROUND it. Cleanup (removing during+to) is awaited via `animationend` OR a
// setTimeout fallback — whichever comes first — so an element with NO animation
// never leaves the helper classes stuck (the op chain itself is not blocked:
// cleanup is fire-and-forget, later ops run immediately). The fallback and the
// listener share a one-shot `done` guard so cleanup runs exactly once.
function runTransition(el, transition, flip) {
  const [during, from, to] = transition
  el.classList.add(during, from)
  flip()
  requestAnimationFrame(() => {
    el.classList.remove(from)
    el.classList.add(to)
  })

  let done = false
  const cleanup = () => {
    if (done) return
    done = true
    el.classList.remove(during, to)
  }
  el.addEventListener("animationend", cleanup, { once: true })
  // ~10% over a common 300ms transition; also the ONLY path for a non-animated
  // element (animationend never fires there), so it must always be scheduled.
  setTimeout(cleanup, 350)
}

// The client-op whitelist behind on_client (issue #95, extended in #96). Mirrors
// Phlex::Reactive::JS's vocabulary; an op name not in this map is
// warn-and-skipped by #applyOps (client-side default-deny — a stale or newer
// ops attr must never break the page). Each op is a pure, local DOM mutation:
// nothing is read back, nothing is sent anywhere. Frozen so nothing can be
// registered into it at runtime — extending the vocabulary is a gem change,
// not an app hook.
const CLIENT_OPS = Object.freeze({
  show: (el, args) => setHidden(el, false, args),
  hide: (el, args) => setHidden(el, true, args),
  toggle: (el, args) => setHidden(el, !el.hidden, args),
  add_class: (el, args) => el.classList.add(...(args.classes ?? [])),
  remove_class: (el, args) => el.classList.remove(...(args.classes ?? [])),
  toggle_class: (el, args) => (args.classes ?? []).forEach((c) => el.classList.toggle(c)),

  // Attribute ops (issue #96), interpret-time allowlisted. set_attr writes the
  // (already-stringified) value; toggle_attr adds a missing attr (value "") or
  // removes a present one; remove_attr removes it. A refused name warns + skips.
  set_attr: (el, args) => {
    if (guardAttr(args.name)) el.setAttribute(args.name, args.value ?? "")
  },
  remove_attr: (el, args) => {
    if (guardAttr(args.name)) el.removeAttribute(args.name)
  },
  toggle_attr: (el, args) => {
    if (!guardAttr(args.name)) return
    if (el.hasAttribute(args.name)) el.removeAttribute(args.name)
    else el.setAttribute(args.name, "")
  },

  // Focus ops (issue #96). focus targets the match itself; focus_first targets
  // its first focusable descendant (opened-menu → first menuitem).
  focus: (el) => el.focus?.(),
  focus_first: (el) => firstFocusable(el)?.focus?.(),

  // Text op (issue #159): set textContent — XSS-safe by construction (never
  // innerHTML), strictly less powerful than set_attr. Change-guarded like
  // #mirrorText. With global: true it is the cross-root text escape: paint a
  // value into a recap node OUTSIDE the component's root.
  text: (el, args) => {
    const text = String(args.value ?? "")
    if (el.textContent !== text) el.textContent = text
  },

  // Dispatch a bubbling CustomEvent (issue #96). RAW element.dispatchEvent — the
  // controller SHADOWS Stimulus's this.dispatch helper, so it must not be used.
  dispatch: (el, args) => {
    el.dispatchEvent(new CustomEvent(args.name, { bubbles: true, composed: true, detail: args.detail ?? {} }))
  },
})

// Apply a hidden-flag change, optionally animated by a [during, from, to]
// transition (issue #96). Split out so show/hide/toggle share it.
function setHidden(el, hidden, args) {
  if (args?.transition) runTransition(el, args.transition, () => (el.hidden = hidden))
  else el.hidden = hidden
}

// The interpret-time attribute guard: refuse (warn + skip) a name off the
// allowlist. Returns true when the op may proceed.
function guardAttr(name) {
  if (!attrRefused(name)) return true
  console.warn(`[phlex-reactive] refused client attr op on ${JSON.stringify(name)} — skipped`)
  return false
}

// A cross-root mirror target must be a single ID selector (issue #159) — "#" +
// a CSS identifier, nothing else. The client half of the two-sided default-deny
// (reactive_compute's `mirror:` validates the SAME shape loudly at declare
// time): a hand-built mirror attr must not widen a declared text mirror into a
// page-wide selector write. A refused selector warns + skips (its siblings
// still apply), matching the attr-allowlist posture.
const MIRROR_ID_SELECTOR = /^#[A-Za-z_][\w-]*$/
function guardMirrorSelector(selector) {
  if (typeof selector === "string" && MIRROR_ID_SELECTOR.test(selector)) return true
  console.warn(`[phlex-reactive] refused cross-root mirror target ${JSON.stringify(selector)} — skipped`)
  return false
}

// Evaluate a show binding's declared literal predicate (issue #161) against
// the controlling field's current value. Exactly one of the three predicate
// attrs decides: equals (value === literal), not (value !== literal), in
// (value ∈ a JSON string list). The vocabulary is fixed and literal-only —
// never an expression, so there is no eval surface (the reactive_show helper
// enforces the same shape loudly at render; this is the client half of the
// two-sided posture). Returns true/false for a decidable binding, or null for
// a malformed/missing predicate — the caller SKIPS a null so a hand-built or
// stale binding never flips visibility it doesn't understand (default-deny,
// like the op whitelist).
function showBindingMatches(el, value) {
  const equals = el.getAttribute("data-reactive-show-equals")
  if (equals !== null) return value === equals
  const not = el.getAttribute("data-reactive-show-not")
  if (not !== null) return value !== not
  const inRaw = el.getAttribute("data-reactive-show-in")
  if (inRaw !== null) {
    try {
      const list = JSON.parse(inRaw)
      if (Array.isArray(list)) return list.includes(value)
    } catch {
      // fall through to the warn below — malformed JSON and a non-array both skip
    }
    console.warn(`[phlex-reactive] malformed reactive_show in: list ${JSON.stringify(inRaw)} — skipped`)
    return null
  }
  // Numeric threshold predicates (issue #176 part B): gte/gt/lte/lt read the
  // literal off its own flat attr and compare Number(value) against it. Any
  // present numeric attr decides the binding — a non-numeric field value (NaN)
  // is false (hidden), and a non-numeric LITERAL warn-skips (null).
  for (const key of SHOW_NUMERIC_KEYS) {
    const raw = el.getAttribute(`data-reactive-show-${key}`)
    if (raw !== null) return numericPredicateMatches(key, raw, value)
  }
  console.warn("[phlex-reactive] a reactive_show binding declares no predicate — skipped")
  return null
}

// The numeric threshold keys (issue #176 part B) — the client half of the Ruby
// SHOW_NUMERIC_KEYS. Order-independent; the evaluator reads the one that's
// present. Each coerces BOTH sides to Number and compares.
const SHOW_NUMERIC_KEYS = ["gte", "gt", "lte", "lt"]

// Evaluate one numeric threshold predicate against a field value. Returns
// true/false for a decidable comparison, or null when the LITERAL itself is
// non-numeric (a malformed binding — warn-skip, default-deny). A non-numeric
// FIELD value (empty/blank/garbage) is treated as NaN → false: the
// reveal-on-threshold notice stays hidden, the safe default. Shared by the
// owned-binding evaluator (raw string literal off an attr) and the
// cross-root/compound evaluator (a literal that arrived as a JSON number or
// string).
function numericPredicateMatches(key, literal, value) {
  const rhs = Number(literal)
  if (Number.isNaN(rhs)) {
    console.warn(`[phlex-reactive] reactive_show ${key}: needs a numeric literal, got ${JSON.stringify(literal)} — skipped`)
    return null
  }
  // A blank/whitespace field value must fail closed. Number("") and
  // Number("   ") are 0 (NOT NaN), so a bare Number()+isNaN check would wrongly
  // reveal a `lte:`/`lt:`/`gte: 0` binding on an EMPTY field. Force the
  // empty/blank case to NaN so the "blank → hidden" contract holds for every
  // operator, not just the ones where 0 happens to fail the comparison.
  const trimmed = value == null ? "" : String(value).trim()
  const n = trimmed === "" ? NaN : Number(trimmed)
  if (Number.isNaN(n)) return false
  switch (key) {
    case "gte":
      return n >= rhs
    case "gt":
      return n > rhs
    case "lte":
      return n <= rhs
    case "lt":
      return n < rhs
    default:
      return null
  }
}

// Evaluate an ALREADY-PARSED show predicate object (issue #164) — the
// reactive_show_targets map embeds { equals/not/in } directly in its JSON, so
// unlike showBindingMatches there are no attrs to read or re-parse. The same
// literal-only vocabulary; anything else (empty, unknown keys, a non-array
// in:) returns null and the caller warn-skips that target (default-deny — a
// hand-built map entry must never flip visibility it doesn't declare).
function showPredicateMatches(pred, value) {
  if (!pred || typeof pred !== "object") return null
  if (typeof pred.equals === "string") return value === pred.equals
  if (typeof pred.not === "string") return value !== pred.not
  if (Array.isArray(pred.in)) return pred.in.includes(value)
  // Numeric threshold predicates (issue #176 part B): the literal arrives as a
  // JSON number (or a numeric string) embedded in the predicate object — one
  // shared numericPredicateMatches with the owned-binding evaluator.
  for (const key of SHOW_NUMERIC_KEYS) {
    if (key in pred) return numericPredicateMatches(key, pred[key], value)
  }
  return null
}

// The selector matching every OWNED-element show binding: single-field
// (data-reactive-show-field, issue #161) OR compound all:/any:
// (data-reactive-show, issue #176). Both the connect() gate and the sync walk
// use it so a compound-only root still enables the sync.
const SHOW_BINDING_SELECTOR = "[data-reactive-show-field], [data-reactive-show]"

// Parse a compound show binding's JSON payload (issue #176 part A). Malformed
// JSON degrades to null WITH a warn — a bad binding must never throw or blank
// the page (client-side default-deny), but a collision (two bindings' JSON
// mix-joined) is worth surfacing.
function parseShowCompound(raw) {
  try {
    const parsed = JSON.parse(raw)
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed
  } catch {
    // fall through to the warn
  }
  console.warn(`[phlex-reactive] malformed compound reactive_show payload ${JSON.stringify(raw)} — skipped`)
  return null
}

// Evaluate one DNF TERM against a resolved field value (issue #180). A missing
// field (null) or a malformed/unknown predicate folds to FALSE — fail-closed
// (default-deny): a broken AND term can't pass, a broken OR term can't reveal.
function dnfTermMatches(term, fieldValue) {
  if (!term || typeof term !== "object" || typeof term.field !== "string") return false
  // An absent owned field reads as "" — identical to the server evaluator
  // (ShowConditions.match? treats a missing field as blank). This keeps the
  // Ruby first-paint and the client live-toggle in exact agreement (the shared
  // fixture proves it). A malformed predicate still folds to false.
  const value = fieldValue(term.field) ?? ""
  return showPredicateMatches(term, value) === true
}

// Evaluate a DNF show payload (issue #180): { any: [group, …] } where each
// GROUP is an array of terms (terms AND within a group, groups OR). Returns
// true/false for a decidable payload, or null for a malformed one (no groups)
// so the caller warn-skips and leaves visibility alone. This is the ONE shape
// the 0.10 wire emits; showPayloadMatches routes the legacy shapes here or to
// the compatibility arm below.
function anyOfAllsMatches(groups, fieldValue) {
  if (!Array.isArray(groups) || groups.length === 0) return null
  // groups OR; within a group, terms AND (an empty group can't decide → false).
  return groups.some((group) => Array.isArray(group) && group.length > 0 &&
    group.every((term) => dnfTermMatches(term, fieldValue)))
}

// Route a parsed data-reactive-show payload to the right evaluator. The 0.10
// wire is { any: [ [term,…], … ] } (DNF — groups are ARRAYS). For a stale tab
// still serving pre-0.10 HTML (deploy overlap), fall back to the 0.9.5 compound
// shape { all: [term,…] } / { any: [term,…] } where the values are flat TERM
// OBJECTS, not arrays. The nesting distinguishes them: DNF's any[0] is an Array.
// DELETE the legacy arm in 0.11.
function showPayloadMatches(payload, fieldValue) {
  if (!payload || typeof payload !== "object") return null
  const any = payload.any
  if (Array.isArray(any) && (any.length === 0 || Array.isArray(any[0]))) {
    return anyOfAllsMatches(any, fieldValue)
  }
  return legacyCompoundShowMatches(payload, fieldValue)
}

// LEGACY (0.9.5, deploy-overlap only — DELETE in 0.11): the flat all:/any:
// compound fold, where terms are objects (not groups). Preserved so a morph of
// stale pre-0.10 HTML doesn't go dead.
function legacyCompoundShowMatches(payload, fieldValue) {
  const connective = Array.isArray(payload.all) ? "all" : Array.isArray(payload.any) ? "any" : null
  if (!connective) return null
  const terms = payload[connective]
  if (terms.length === 0) return null
  const results = terms.map((term) => dnfTermMatches(term, fieldValue))
  return connective === "all" ? results.every(Boolean) : results.some(Boolean)
}

// A cross-root show target must be a single ID selector (issue #164) — the
// SAME shape the #159 mirror enforces (one shared regex), with its own warn so
// a refused show target is distinguishable in the console. The client half of
// the two-sided default-deny: reactive_show_targets raises at declare time; a
// hand-built wire attr must not widen the escape to class/compound selectors.
// A refused selector warns + skips — its siblings still apply.
function guardShowTargetSelector(selector) {
  if (typeof selector === "string" && MIRROR_ID_SELECTOR.test(selector)) return true
  console.warn(`[phlex-reactive] refused cross-root show target ${JSON.stringify(selector)} — skipped`)
  return false
}

// The first focusable descendant of `el`, in document order — the natural
// keyboard target inside an opened menu/dialog. Covers the standard focusable
// set; :not([tabindex="-1"]) drops explicitly-removed nodes. Returns null when
// nothing inside is focusable (focus_first then no-ops).
const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
function firstFocusable(el) {
  return el.querySelectorAll?.(FOCUSABLE)?.[0] ?? null
}

// Parse a [[name, args], ...] op list from a raw attr/param. An array passes
// through; a JSON string is parsed; anything malformed degrades to [] — a bad
// ops attr must NEVER break the page (client-side default-deny). Shared by the
// controller's runOps and the reactive:js stream action (issue #97).
function parseOps(raw) {
  if (Array.isArray(raw)) return raw
  if (typeof raw !== "string") return []
  try {
    const list = JSON.parse(raw)
    return Array.isArray(list) ? list : []
  } catch {
    return []
  }
}

// Interpret a [[name, args], ...] op list against the frozen CLIENT_OPS
// whitelist (issues #95/#96/#97). `resolveTargets(args)` returns the element(s)
// an op applies to — the controller scopes to its root (excluding nested
// reactive roots); the reactive:js stream action scopes to its target root (or
// the document). An unknown name warns and is SKIPPED while the rest of the
// chain still applies — client-side default-deny, one bad op never takes down
// its siblings. Object.hasOwn (not a bare read) so inherited Object members
// ("constructor") can't masquerade as ops.
function applyOps(list, resolveTargets) {
  for (const entry of list) {
    if (!Array.isArray(entry)) continue
    const [name, args = {}] = entry
    if (!Object.hasOwn(CLIENT_OPS, name)) {
      console.warn(`[phlex-reactive] unknown client op ${JSON.stringify(name)} — skipped`)
      continue
    }
    for (const el of resolveTargets(args)) CLIENT_OPS[name](el, args)
  }
}

// Resolve a reactive:js op's targets against its `target` root (issue #97).
// "@root" is the root element itself; a selector resolves WITHIN it; a bare
// selector with no root (no `target` attr on the stream) resolves document-wide
// — a broadcast op anchored by a global selector (#bell) rather than a
// component. Unlike the controller path there is no nested-reactive-root
// ownership filter: a server-pushed op names its own scope explicitly —
// including `global: true`, which opts a single op out of the target-root
// scope to document-wide resolution (issue #159; the same escape the builder
// documents for the controller path).
function streamOpTargets(args, root) {
  const to = args.to
  if (root) {
    if (to === "@root") return [root]
    if (typeof to !== "string" || to === "") return []
    if (args.global) return [...document.querySelectorAll(to)]
    return [...root.querySelectorAll(to)]
  }
  // No target root: document-scoped. "@root" is meaningless here (nothing to
  // anchor to) → no-op; a selector matches document-wide.
  if (typeof to !== "string" || to === "" || to === "@root") return []
  return [...document.querySelectorAll(to)]
}

// Register this controller eagerly (not lazily) so a click immediately after
// page load is never missed. The phlex-reactive engine auto-pins it with
// preload: true for importmap apps; see the README for esbuild/webpack.
export default class extends Controller {
  static values = {
    token: String, // signed identity token (component + record gid/state)
  }

  #tokenCache // freshest token, threaded synchronously across queued requests
  #debounceTimers = new Map() // trigger element -> { timer, flush } pending dispatch
  #throttleTimers = new Map() // trigger element -> Map(action -> suppression timer)
  #actionPathCache // page-stable action path, resolved once per controller
  #timeoutMsCache // page-stable request timeout (ms), resolved once per controller (issue #101)
  #tokenRegexCache // { id, token, self } — #extractToken's two per-id RegExps, rebuilt on id change (issue #118)
  // Loading-state bookkeeping (issue #99). All keyed so overlapping enqueues
  // refcount correctly and never clobber each other:
  #busyPending = 0 // root aria-busy pending counter (remove only at zero)
  #busyActions = new Map() // action -> in-flight count (root's space-separated busy set + busy_on)
  #busyTokenCounts = new WeakMap() // element -> Map(action -> count): its data-reactive-busy token set
  #textDisableSnapshots = new Map() // trigger -> { count, disabled, html } refcounted text/disable snapshot (issue #181)
  // Issue #183: the `input` events recompute dispatches for its OWN output writes,
  // marked so a re-entrant recompute on THIS root skips re-running the reducer
  // (single-pass write set). Per-instance, so another root's events are never
  // swallowed. WeakSet: entries drop when the short-lived Event is GC'd.
  #computeSelfDispatched = new WeakSet()
  // Dirty tracking (issue #103): the bound re-scan (turbo:morph-element) and the
  // navigate-away guard handlers, held so disconnect() can remove exactly them.
  #boundScanDirty
  #boundBeforeUnload
  #boundBeforeVisit
  // Show bindings (issue #161): the ONE delegated sync handler shared by the
  // root's input/change/turbo:morph-element listeners, held for teardown.
  #boundSyncShow
  // Option filtering (issue #163): the ONE delegated sync handler shared by the
  // root's input/turbo:morph-element listeners, held for teardown.
  #boundSyncFilter
  // Lazy initial mount (issue #165): the bound re-probe attached to
  // turbo:morph-element so a Turbo page-refresh morph re-fires the defer fetch.
  #boundProbeLazyDefer

  // Mark that a reactive controller actually connected, so the registration
  // guard above knows the controller was registered (issue #26 part 2).
  connect() {
    reactiveConnected = true

    // Root-id guard (issue #48). The token round trip assumes the reactive root
    // element's id == component.id: the server targets component.id and the client
    // self-matches its NEXT token by this.element.id (#extractToken, issue #46).
    // If `id:` landed on a CHILD instead of the `**reactive_attrs` root, this id is
    // "" — #extractToken falls back to the FIRST token in the response (a child's),
    // so the next action POSTs a foreign token → endpoint default-deny → silent 403.
    // Warn NOW (on connect) so the failure surfaces on page load, not on click 2.
    if (this.element.id === "") {
      console.warn(
        "[phlex-reactive] a reactive root has no id; its next-action token can't self-match " +
          "and may fall back to the first token in the response → a silent HTTP 403 on the NEXT action. " +
          "Put id: on the SAME element as reactive_attrs — use div(**reactive_root) (emits id + token together), " +
          "or div(id:, **reactive_attrs). The id: must NOT be on a child. See the README."
      )
    }

    // Lazy initial mount (issue #165): a reactive_lazy shell carries its defer
    // token as a ROOT attribute — enter the SAME module-level fetch path a
    // reply directive uses (supersession, pending markers, error handling
    // included). Probe on connect (a plain replace / cache restoration
    // re-connects) AND on turbo:morph-element: a Turbo page-refresh MORPH
    // re-shows the shell while keeping the element CONNECTED and firing no
    // Stimulus lifecycle, so a connect-only probe would leave the morphed-in
    // shell shimmering forever. The supersession registry makes a duplicate
    // probe a no-op (same target id), so re-probing is safe. The attribute
    // stays on the shell precisely so a re-appearance re-fires.
    // Only wire the morph re-probe for a root that IS a lazy shell (carries the
    // token) — a component that never uses reactive_lazy pays nothing (no
    // listener), matching the dirty-tracking / show-sync gating precedent.
    if (this.element.getAttribute?.("data-reactive-defer-token")) {
      this.#probeLazyDefer()
      this.#boundProbeLazyDefer = () => this.#probeLazyDefer()
      this.element.addEventListener?.("turbo:morph-element", this.#boundProbeLazyDefer)
    }

    // Dirty tracking (issue #103) — ONLY when this root opts in (track_dirty: or a
    // reactive_field(dirty:)), so a component that never uses it pays nothing (no
    // baseline scan, no morph listener on every broadcast). A plain (outerHTML)
    // replace re-connects the controller, so seed the baseline scan here — the root
    // reflects current-vs-default WITHOUT waiting for the first input. An in-place
    // morph / broadcast morph keeps the element CONNECTED and fires no Stimulus
    // lifecycle, so ALSO listen for turbo:morph-element on this.element to re-scan
    // after the morph writes fresh default* attributes (reactive:applied is NOT a
    // valid hook — it fires when streams are handed to Turbo, BEFORE the DOM
    // mutation). Both listeners are torn down in disconnect().
    if (this.#dirtyTrackingEnabled()) {
      this.#boundScanDirty = () => this.#scanDirty()
      this.element.addEventListener?.("turbo:morph-element", this.#boundScanDirty)
      this.#scanDirty()

      // warn_unsaved: arm a navigate-away guard gated on a LIVE dirty-count read
      // (never a cached snapshot — the count is re-derived from the DOM each time).
      // beforeunload covers a real browser unload; turbo:before-visit covers a
      // Turbo in-app navigation (it does NOT fire on restoration visits — the
      // documented gap). Registered on window only when the marker is present.
      if (this.element.getAttribute?.("data-reactive-warn-unsaved") === "true") {
        this.#armUnsavedGuard()
      }
    }

    // Show bindings (issue #161) — ONLY when this root owns one, so a component
    // without any pays a single probe (the dirty-tracking gate precedent). ONE
    // delegated listener pair on the root (input + change bubble from every
    // owned field — no per-field wiring, and a reactive_compute output write
    // dispatches a real input event, so computed values drive visibility too).
    // The connect sync seeds the initial state — a plain replace re-connects —
    // and turbo:morph-element re-syncs after an in-place morph (which keeps the
    // element connected, fires no Stimulus lifecycle, and may preserve a
    // user-edited field value the server's hidden attrs don't reflect).
    if (this.#showSyncEnabled()) {
      this.#boundSyncShow = () => this.#syncShow()
      this.element.addEventListener?.("input", this.#boundSyncShow)
      this.element.addEventListener?.("change", this.#boundSyncShow)
      this.element.addEventListener?.("turbo:morph-element", this.#boundSyncShow)
      this.#syncShow()
    }

    // Option filtering (issue #163) — ONLY when the root declares the binding
    // (reactive_filter emits both attrs together), so a component without one
    // pays two attribute reads. ONE delegated input listener on the root — the
    // handler re-filters only for events from the NAMED input, so keystrokes in
    // unrelated fields on a wide form never pay a filter pass. The connect sync
    // seeds from the input's current value (a plain replace re-connects; back
    // navigation may restore typed text), and turbo:morph-element re-applies
    // after an in-place morph (which keeps the element connected, fires no
    // Stimulus lifecycle, and may preserve the user's typed query while the
    // server re-rendered every option visible).
    if (this.#filterEnabled()) {
      this.#boundSyncFilter = (event) => {
        if (event?.type === "input" && !this.#filterInputEvent(event)) return
        this.#syncFilter()
      }
      this.element.addEventListener?.("input", this.#boundSyncFilter)
      this.element.addEventListener?.("turbo:morph-element", this.#boundSyncFilter)
      this.#syncFilter()
    }
  }

  // Whether this root opts into dirty tracking (issue #103): track_dirty: puts the
  // trackDirty descriptor on the ROOT's data-action; a per-field reactive_field(
  // dirty:) puts it on a descendant field. Either turns tracking on. A quick
  // attribute read + one scoped query, evaluated once per connect (a cold path).
  #dirtyTrackingEnabled() {
    if ((this.element.getAttribute?.("data-action") ?? "").includes("reactive#trackDirty")) return true
    const nodes = this.element.querySelectorAll?.('[data-action*="reactive#trackDirty"]') ?? []
    for (const el of nodes) if (this.#ownsField(el)) return true
    return false
  }

  // Tear down any pending debounce timers when the controller leaves the DOM
  // (Turbo morph/navigation removes the element). Otherwise a timer that hasn't
  // fired yet would later call #enqueue on a disconnected controller — a round
  // trip against a detached element / stale token (issue #17 follow-up).
  // Throttle suppression timers (issue #80) are torn down the same way — a
  // leading-edge timer holds no pending POST, but leaving it running would leak
  // it past the element's life.
  disconnect() {
    this.#clearAllDebounces()
    this.#clearAllThrottles()
    this.#teardownDirtyTracking()
    this.#teardownShowSync()
    this.#teardownFilterSync()
    if (this.#boundProbeLazyDefer) {
      this.element.removeEventListener?.("turbo:morph-element", this.#boundProbeLazyDefer)
    }
  }

  // Lazy initial mount probe (issue #165): fetch the real content when THIS
  // root is a reactive_lazy shell that still carries its defer token AND the
  // pending marker. Gating on the pending marker is what makes a re-probe (a
  // Turbo morph re-showing the shell) fire while a re-probe of an already
  // RESOLVED root (real content, no token, no marker) is a no-op. The
  // module-level supersession registry dedupes a duplicate in-flight fetch for
  // the same id, so calling this on both connect and every morph is safe.
  #probeLazyDefer() {
    const el = this.element
    if (!el?.id) return
    const token = el.getAttribute?.("data-reactive-defer-token")
    if (!token) return
    if (el.getAttribute?.("data-reactive-defer-pending") !== "true") return
    startFetchDefer(el.id, token)
  }

  // Serialize requests per component. Each round trip rewrites the signed
  // token in the DOM (state lives in the token, not the client). If events
  // fire faster than round trips complete, concurrent requests would all read
  // the SAME stale token and clobber each other (last-write-wins). Chaining on
  // a per-controller promise makes each dispatch wait for the previous one, so
  // it always uses the freshest token.
  dispatch(event) {
    // `window` (renamed: never shadow the global) and `outside` are the event-
    // modifier params (issue #80). The client decides preventDefault behavior
    // from event.params — set by the Ruby on() — never by sniffing the
    // Stimulus descriptor.
    const { action, params, debounce, throttle, confirm, outside, window: windowBound, optimistic } =
      event.params
    if (!action) return

    // The pending-state hint (issue #181): data-reactive-busy-param. During a
    // deploy overlap a page rendered by the PREVIOUS gem still emits the old
    // data-reactive-loading-param — read it as a fallback so an in-flight page
    // keeps its pending affordance until the next full render. The old `class:`
    // key is remapped to add_class: so it flows through the one hint applier.
    const busy = event.params.busy ?? this.#legacyLoadingHint(event.params.loading)

    // Outside guard FIRST (issue #80): an outside: trigger only fires for
    // events whose target is OUTSIDE this component's ROOT (containment against
    // this.element — .contains includes the root itself). An event inside the
    // root must be a COMPLETE no-op — before preventDefault (the page's native
    // click behavior is untouched) and before the reactive:before-dispatch
    // lifecycle event (nothing to announce, nothing to veto).
    if (outside && this.element.contains(event.target)) return

    // The trigger is event.currentTarget — the element on(...) was spread onto —
    // NOT event.target (issue #99). A `<button><span>Save</span></button>` click
    // has target === the span, which carries no params and is the wrong element
    // to disable / swap text on. currentTarget is the bound element; fall back to
    // target for a directly-invoked/synthetic event. Captured now because
    // #proceed runs in a later microtask (after the confirm resolver), by which
    // point currentTarget is reset to null.
    const target = event.currentTarget ?? event.target

    // Stop native behavior (button submit / FORM NAVIGATION) HERE, synchronously
    // within the event dispatch — BEFORE the (possibly async) confirm gate below.
    // preventDefault() only works while the event is still being handled; once we
    // await the confirm resolver it's too late, and a `submit` trigger would
    // natively POST the form and navigate before the reactive round trip runs
    // (issue #11). For a `click` trigger there's no default to miss. This holds
    // for debounced triggers too — the round trip is deferred, but the native
    // default must still be prevented now. (Moved ahead of the confirm branch in
    // issue #55: an async resolver means we can't preventDefault after awaiting.)
    //
    // ONLY for element-bound triggers: a window-bound trigger (window:/outside:,
    // issue #80) hears EVERY matching event on the page — preventDefault-ing
    // those would kill every link click while a dropdown is mounted. The page's
    // native behavior proceeds alongside the reactive round trip.
    //
    // The `checked: :keep` optimistic hint (issue #98) OPTS OUT: for a click-bound
    // checkbox/radio the unconditional preventDefault is exactly what stops the
    // native flip from happening before the morph — so a bare checkbox click
    // (which has no form-navigation default to lose) skips it and flips now, and
    // the failure revert snaps it back. A `change`-bound trigger is unaffected —
    // `change` isn't cancelable, so preventDefault was already a no-op there.
    if (!windowBound && !this.#keepsNativeToggle(optimistic, target)) event.preventDefault()

    // No confirm message → proceed straight away (unchanged fast path).
    if (!confirm) return this.#proceed(target, action, params, debounce, throttle, optimistic, busy)

    // Confirmation gate (issue #52, made overridable + async in #55). A reactive
    // trigger can't use Hotwire's data-turbo-confirm — this controller preempts
    // the event — so a `confirm:` message routes through confirmResolver (default
    // window.confirm; an app can override it to reuse Turbo.config.forms.confirm).
    // The resolver may be sync or async; call it INSIDE the chain (via the leading
    // .then) so even a SYNCHRONOUS override throw rejects this promise instead of
    // escaping dispatch — a throwing dialog is treated as a cancel, like the user
    // dismissing it. The .catch is scoped to the resolver step (→ false = cancel),
    // so a dismissed/erroring dialog never surfaces as an unhandled rejection AND a
    // genuine bug inside #proceed is NOT silently swallowed. Enqueue ONLY on a
    // truthy resolution — nothing is enqueued, no timer scheduled, otherwise.
    Promise.resolve()
      .then(() => confirmResolver(confirm))
      .catch(() => false)
      .then((ok) => {
        if (ok) this.#proceed(target, action, params, debounce, throttle, optimistic, busy)
      })
  }

  // CLIENT-ONLY trigger entry point (issue #95) — the zero-round-trip sibling
  // of dispatch(). Wired by on_client: applies the declared op chain
  // (data-reactive-ops-param, built by Phlex::Reactive::JS) locally. NO token,
  // NO params, NO fetch, ever. Ops are ephemeral UI: any server re-render of
  // the component resets whatever they toggled (by design — a signed action
  // owns state that must survive re-renders).
  runOps(event) {
    const { ops, confirm, outside, window: windowBound } = event.params

    // Outside guard FIRST — identical semantics to dispatch() (issue #80): an
    // outside: trigger is a COMPLETE no-op for events inside this root, before
    // preventDefault and before any op runs.
    if (outside && this.element.contains(event.target)) return

    // Element-bound triggers preventDefault (a bare button inside a <form>
    // must not submit it); window-bound triggers (window:/outside:) never do —
    // they hear every matching event on the page, and preventDefault-ing those
    // would kill native clicks site-wide (issue #80 rationale). Runs BEFORE the
    // (possibly async) confirm gate below — a native default can't wait for a
    // pending dialog (same ordering as dispatch()).
    if (!windowBound) event.preventDefault()

    // No confirm → apply straight away (unchanged fast path, no prompt).
    if (!confirm) return this.#applyOps(this.#parseOps(ops))

    // Confirmation gate for client ops (issue #178) — the SAME confirmResolver
    // gate on(:action, confirm:) uses (issues #52/#55), reused verbatim so a
    // themed dialog set with setConfirmResolver covers BOTH paths. A destructive
    // client op (clear a draft, reset a form) gets the one-line themed confirm
    // without a round trip. Call the resolver INSIDE the chain (leading .then)
    // so even a SYNCHRONOUS override throw rejects here instead of escaping
    // runOps — a throwing dialog is a cancel, like dismissing it. The gate is
    // here (the user gesture), NOT in #applyOps: that applier is shared with the
    // server-pushed reactive:js stream action, which must NEVER prompt.
    Promise.resolve()
      .then(() => confirmResolver(confirm))
      .catch(() => false)
      .then((ok) => {
        if (ok) this.#applyOps(this.#parseOps(ops))
      })
  }

  // Dirty tracking (issue #103). Wired by reactive_field(dirty: true) /
  // reactive_root(track_dirty: true): an `input` on an owned field runs a FULL
  // re-scan of every field this root owns. NO round trip, NO shipped state — the
  // baseline is the DOM's own defaultValue/defaultChecked/defaultSelected (the
  // last server render). A full pass (not a per-target toggle) is essential for
  // radio groups: the deselected radio flips to checked=false and fires no input
  // event, so only re-scanning everything keeps its flag honest.
  trackDirty() {
    this.#scanDirty()
  }

  // Client-side compute (data binding). Wired by reactive_compute: an `input`
  // trigger (input->reactive#recompute) runs a REGISTERED JS reducer over the
  // named input fields and writes the named output fields WITH NO ROUND TRIP —
  // the "instant" half of the new/unpersisted-record UX. If the field ALSO
  // carries on(...) (a persisted record, or a synced draft), that debounced POST
  // still fires and the server reply reconciles; recompute just paints first.
  //
  // Reads inputs/outputs/reducer from the root's data-reactive-compute-* attrs
  // (set once by reactive_compute_attrs). A missing/unregistered reducer is a
  // no-op — a page must never break because a binding wasn't wired up.
  //
  // The reducer gets a second argument, meta = { changed } (issue #75): the
  // name of the declared input the triggering event edited, or null for a
  // direct call / an unowned or undeclared target. A multi-way rebalance
  // branches on it (edit c → derive a; else → derive c). Note that a #76
  // output write dispatches a real input event, so recompute RE-ENTERS with
  // changed = that output's name — the reducer must be convergent (see
  // compute.js) so the change guard settles the chain.
  recompute(event) {
    // Issue #183 — single-pass write set: an `input` event this method dispatched
    // for its OWN output writes is self-marked. Re-running the reducer on it would
    // re-enter from a partially-written DOM (the old mid-loop-dispatch corruption
    // class). Skip the reducer for our own event — but ONLY ours: the marker lives
    // in a per-instance WeakSet, so a genuinely different root's compute event (or
    // a real user edit) is never swallowed. The event still bubbled and fired every
    // OTHER listener (dirty tracking, show bindings, sibling roots) before reaching
    // here; we simply don't recompute a second time from our own write.
    if (event && this.#computeSelfDispatched.has(event)) return

    // Inputs may be a JSON ARRAY of names (array form — every input coerced
    // through Number, the shipped behavior) or a JSON OBJECT of name→type (hash
    // form, issue #104 — :number coerced, :string read raw). #parseComputeInputs
    // returns [name, type] pairs either way (array form defaults type "number").
    const inputPairs = this.#parseComputeInputs()
    const inputs = inputPairs.map(([name]) => name)

    // Resolve every declared input AND output through ONE per-call resolver whose
    // ownership probe is computed ONCE (issue #117), replacing the per-name
    // closest() walk #ownedField did on every read — a 30-field calculator paid
    // ~60 closest() sweeps per keystroke. #ownershipFilter returns a constant-true
    // predicate in the common no-nested-root case (skipping closest() entirely)
    // and the exact #ownsField check when a nested reactive root is present
    // (issue #15 scoping, byte-identical to before). Resolution is memoized in a
    // per-CALL Map, FIRST-WINS, so a name read as an input AND written as an
    // output resolves to the SAME element and is queried once.
    //
    // Why per-name `[name="X"]` queries and not one bare `[name]` sweep: a single
    // sweep is the natural "one walk", but the resolver must issue the SAME
    // per-name query shape the field walk always has (the issue-#15 unit fakes
    // answer only `[name="X"]`). It is O(distinct declared names) queries, not the
    // old O(inputs + outputs) — the ownership decision is hoisted out of the loop.
    // The memo is per-CALL only: an output write dispatches `input` (issue #76),
    // re-entering recompute, which correctly rebuilds a fresh map (a morph may
    // have replaced the nodes) — it is NEVER stored on the instance.
    // Scope (issue #183, mirroring #showFieldValue): a bare compute name `cash`
    // under `data-reactive-scope="order"` resolves as `[name="order[cash]"]`. A
    // name already carrying a bracket (a raw wire name the author passed) is used
    // verbatim — so bracketed literals pass through unscoped.
    const scope = this.element.getAttribute?.("data-reactive-scope") || null
    const scoped = (name) => (scope && !name.includes("[") ? `${scope}[${name}]` : name)

    const owns = this.#ownershipFilter()
    const byName = new Map()
    const ownedField = (name) => {
      if (byName.has(name)) return byName.get(name)
      let found = null
      for (const el of this.element.querySelectorAll(`[name="${scoped(name)}"]`)) {
        if (owns(el)) {
          found = el // FIRST-WINS (radio groups, Rails hidden+checkbox name pairs)
          break
        }
      }
      byName.set(name, found)
      return found
    }

    // Identity-mirror pass (issue #104), ALWAYS run — even with NO registered
    // reducer, so reactive_text(:title) mirrors a field into its text node with
    // zero reducer wiring. Each declared input's RAW string value is written to
    // its owned [data-reactive-text="<name>"] node(s). It runs BEFORE the reducer
    // early-return below so a reducer-less binding still mirrors.
    for (const name of inputs) this.#mirrorText(name, ownedField(name)?.value ?? "")

    const key = this.element.getAttribute("data-reactive-compute-reducer-param")
    const reduce = key ? computeReducer(key) : null
    if (!reduce) {
      // No reducer registered: the identity pass above still ran, so declared
      // cross-root mirrors of the INPUT names still paint (issue #159) — a
      // reducer-less binding mirrors, exactly like the owned-text-node case.
      this.#applyComputeMirrors({}, ownedField)
      return
    }

    const outputs = this.#parseComputeList("data-reactive-compute-outputs-param")

    // Coerce each input per its declared type (issue #104): "string" → the raw
    // display string (blank/absent → ""); else ("number", the array-form default)
    // → the numeric coercion (blank/NaN → 0, the nanToZero the hand-written
    // calculators use). Reads from the memoized resolver — no re-query.
    const values = {}
    for (const [name, type] of inputPairs) {
      const field = ownedField(name)
      if (type === "string") {
        values[name] = field?.value ?? ""
      } else {
        const n = Number(field?.value)
        values[name] = Number.isFinite(n) ? n : 0
      }
    }

    // meta.changed stays on #changedComputeField (its own #ownsField check over
    // the raw event target) — NOT this resolver. The issue-#15 nested-rejection
    // test depends on that path being unchanged. ONE run, from the ONE pre-write
    // snapshot above (issue #183): its result drives the whole single-pass write.
    const result = reduce(values, { changed: this.#changedComputeField(event, inputs, scope) }) || {}

    // Issue #183 — SINGLE-PASS WRITE SET. Three ordered phases, so declared output
    // order stops being semantics and a wrong order can no longer corrupt values:
    //
    //   1. BATCH the field writes from the ONE result. Each output name in the
    //      allowlist (outputs:) whose owned field's value actually changes is
    //      written now (change-guarded) and remembered — but NO `input` event is
    //      dispatched yet, so nothing re-enters mid-batch.
    //   2. PAINT the sinks from the SETTLED values: any owned reactive_text node by
    //      presence (issue #183 change #4 — a text node no longer needs its name in
    //      outputs:), then the cross-root mirror: ids (issue #159).
    //   3. DISPATCH a self-marked `input` on each changed field. The marker (a
    //      per-instance WeakSet) makes recompute skip re-running the reducer for our
    //      own write, while the event still fires every OTHER listener (chained
    //      repaint, dirty tracking, show bindings, sibling roots).
    const changedFields = []
    for (const name of outputs) {
      if (!(name in result)) continue
      const field = ownedField(name)
      if (!field) continue // a non-field output paints as a text sink in phase 2
      if (String(result[name]) === field.value) continue // change-guard — unchanged, skip
      field.value = result[name]
      changedFields.push(field)
    }

    // Phase 2 — text sinks declare themselves (issue #183 change #4): every result
    // key paints into any owned [data-reactive-text="<name>"] node by PRESENCE,
    // regardless of outputs: membership. Runs from settled field values. A null/
    // undefined result value is SKIPPED (never stringified to "null"/"undefined") —
    // the same "no value this pass, don't paint" filter #applyComputeMirrors uses.
    for (const name of Object.keys(result)) {
      const value = result[name]
      if (value === undefined || value === null) continue
      this.#mirrorText(name, value)
    }

    // Cross-root text mirrors (issue #159) — AFTER the batch + text sinks, so a
    // mirror keyed on a just-written output paints the settled value.
    this.#applyComputeMirrors(result, ownedField)

    // Phase 3 — dispatch the deferred `input` events (issue #183). Real browsers
    // do NOT fire `input` on a programmatic .value write (issue #76), so we do it
    // ourselves, matching the server's set_value + dispatch("input") contract.
    // Each event is SELF-MARKED so our own re-entry skips the reducer (guard at the
    // top of recompute) — but the event still bubbles and fires every other
    // listener. Dispatched AFTER all writes + paints, so a chained listener reads
    // SETTLED values, never a half-written DOM.
    for (const field of changedFields) {
      const inputEvent = new Event("input", { bubbles: true })
      this.#computeSelfDispatched.add(inputEvent)
      field.dispatchEvent(inputEvent)
    }
  }

  // Client-side list navigation (combobox keyboard nav, issue #72). Wired by
  // on(:search, …, listnav: "[role=option]"), which appends keyboard filters to
  // the input's data-action (keydown.down/up/enter/esc->reactive#listnav*) and
  // sets data-reactive-listnav-option-param. Arrow keys move a highlight among
  // the options WITH NO ROUND TRIP; Enter picks the highlighted option by
  // CLICKING IT (so its own on(:select) reactive trigger fires — selection stays
  // a signed action); Escape clears. Ephemeral highlight state lives on the DOM
  // (data-reactive-highlighted), never shipped to the client as trusted state.
  listnavNext(event) {
    this.#moveHighlight(event, +1)
  }

  listnavPrev(event) {
    this.#moveHighlight(event, -1)
  }

  // Enter: activate the highlighted option (fires its reactive select). No-op if
  // nothing is highlighted, and in that case DON'T preventDefault — Enter falls
  // through (there's no selection to make).
  listnavPick(event) {
    const options = this.#listnavOptions(event)
    const current = options.findIndex((el) => el.hasAttribute("data-reactive-highlighted"))
    if (current < 0) return
    event.preventDefault()
    options[current].click()
  }

  listnavClose(event) {
    for (const el of this.#listnavOptions(event)) el.removeAttribute("data-reactive-highlighted")
  }

  // Move the highlight by `step` (with wrap-around) among THIS root's options.
  // preventDefault stops Arrow keys from moving the caret in the search input.
  #moveHighlight(event, step) {
    const options = this.#listnavOptions(event)
    if (!options.length) return
    event.preventDefault()

    const current = options.findIndex((el) => el.hasAttribute("data-reactive-highlighted"))
    // From nothing: Down highlights the first option, Up the last.
    const next = current < 0 ? (step > 0 ? 0 : options.length - 1) : (current + step + options.length) % options.length

    for (const el of options) el.removeAttribute("data-reactive-highlighted")
    const chosen = options[next]
    chosen.setAttribute("data-reactive-highlighted", "true")
    chosen.scrollIntoView?.({ block: "nearest" })
  }

  // The option elements this root owns (skips nested reactive roots, issue #15),
  // per the selector on data-reactive-listnav-option-param. The attr rides on the
  // TRIGGER element (the search input on(...) is spread onto), read from the
  // event; the options are still scoped to this controller's root. Empty when
  // unset. Falls back to the root for a directly-invoked call (unit tests). The
  // ownership predicate is hoisted ONCE per keypress (issue #117) — in the common
  // no-nested-root case it is a constant true, skipping a closest() walk per
  // option. Hidden options are excluded (issue #163): a reactive_filter (or any
  // `hidden` toggle) removes a row from the keyboard path too, so an Arrow can't
  // highlight — and Enter can't pick — an invisible option.
  #listnavOptions(event) {
    const trigger = event?.currentTarget ?? event?.target ?? this.element
    const selector =
      trigger.getAttribute?.("data-reactive-listnav-option-param") ??
      this.element.getAttribute("data-reactive-listnav-option-param")
    if (!selector) return []
    const owns = this.#ownershipFilter()
    return Array.from(this.element.querySelectorAll(selector)).filter((el) => !el.hidden && owns(el))
  }

  // Parse a JSON string list from a root data attr; [] on absence/parse error so
  // a malformed binding degrades to "no fields" rather than throwing on input.
  #parseComputeList(attr) {
    const raw = this.element.getAttribute(attr)
    if (!raw) return []
    try {
      const list = JSON.parse(raw)
      return Array.isArray(list) ? list : []
    } catch {
      return []
    }
  }

  // Parse the inputs param into [name, type] pairs (issue #104). The wire is a
  // JSON ARRAY of names (array form → every input typed "number", the shipped
  // numeric coercion) OR a JSON OBJECT of name→type (hash form → ":string" read
  // raw, ":number" coerced). Malformed/absent degrades to [] — a bad binding
  // must never throw on input.
  #parseComputeInputs() {
    const raw = this.element.getAttribute("data-reactive-compute-inputs-param")
    if (!raw) return []
    try {
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed)) return parsed.map((name) => [name, "number"])
      if (parsed && typeof parsed === "object") return Object.entries(parsed)
      return []
    } catch {
      return []
    }
  }

  // The declared compute input the event just edited — the reducer's
  // meta.changed (issue #75). The triggering field counts only when it is a
  // named form control OWNED by this root (not a nested reactive root's, issue
  // #15) AND its name is among the declared compute inputs; anything else
  // (a direct call, an unowned/undeclared target) yields null.
  //
  // Scope-aware (issue #184): under data-reactive-scope, the edited field's DOM
  // name is scoped (order[allowance]) while the declared inputs are BARE
  // (allowance). Strip the scope prefix off the DOM name before comparing, and
  // return the BARE name — so a reducer branching on `changed` sees the same
  // names it declared, scoped or not.
  #changedComputeField(event, inputs, scope) {
    const target = event?.target
    if (!target?.name || typeof target.closest !== "function") return null
    const bare = this.#unscopeName(target.name, scope)
    if (!inputs.includes(bare)) return null
    return this.#ownsField(target) ? bare : null
  }

  // Strip a leading `scope[…]` wrapper off a DOM field name, returning the bare
  // inner name; a name that isn't wrapped in this scope passes through unchanged.
  #unscopeName(name, scope) {
    if (!scope) return name
    const prefix = `${scope}[`
    return name.startsWith(prefix) && name.endsWith("]") ? name.slice(prefix.length, -1) : name
  }

  // Write `value` into every owned [data-reactive-text="<name>"] node via
  // textContent (issue #104) — XSS-safe by construction (never innerHTML). Drives
  // both the identity mirror (an input's raw value) and a text-node output (a
  // reducer result with no matching field). Change-guarded (skip an unchanged
  // node) and NO input dispatch — a text node has no listener contract. String()
  // so a numeric result renders like the DOM would.
  #mirrorText(name, value) {
    const text = String(value)
    for (const node of this.#ownedTextNodes(name)) {
      if (node.textContent === text) continue
      node.textContent = text
    }
  }

  // Every [data-reactive-text="<name>"] mirror OWNED by this root (skips nested
  // reactive roots, issue #15). Empty when none — reactive_text is optional.
  #ownedTextNodes(name) {
    const nodes = this.element.querySelectorAll(`[data-reactive-text="${name}"]`)
    return Array.from(nodes).filter((el) => this.#ownsField(el))
  }

  // Cross-root text mirrors (issue #159): paint every DECLARED mirror name into
  // its allowlisted document-wide id targets via textContent — the opt-in escape
  // from root isolation (issue #15) for a recap OUTSIDE the computing root. The
  // value is the reducer's result when it produced one, else the owned field's
  // CURRENT value (an input identity mirror / a just-written output) — one
  // declaration covers all three shapes. A name with NO value this pass is
  // SKIPPED (a mirror never blanks a recap the reducer didn't feed). textContent
  // only (never innerHTML), change-guarded, and NO input dispatch — same
  // contract as #mirrorText. With no mirror declared this is one getAttribute
  // and out — the shipped compute path never touches the document.
  #applyComputeMirrors(result, ownedField) {
    const mirror = this.#parseComputeMirror()
    for (const [name, selectors] of Object.entries(mirror)) {
      const value = name in result ? result[name] : ownedField(name)?.value
      if (value === undefined || value === null) continue
      const text = String(value)
      for (const sel of Array.isArray(selectors) ? selectors : [selectors]) {
        if (!guardMirrorSelector(sel)) continue
        for (const node of document.querySelectorAll(sel)) {
          if (node.textContent === text) continue
          node.textContent = text
        }
      }
    }
  }

  // The declared cross-root mirror map (issue #159): a JSON object of
  // { name: [id selectors] } from data-reactive-compute-mirror-param (emitted by
  // reactive_compute's `mirror:`). Absent/malformed degrades to {} — a bad
  // binding must never throw on input.
  #parseComputeMirror() {
    const raw = this.element.getAttribute("data-reactive-compute-mirror-param")
    if (!raw) return {}
    try {
      const parsed = JSON.parse(raw)
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch {
      return {}
    }
  }

  // Enqueue the action — debounced if a debounce window is set, else immediately.
  // Split out of dispatch so both the no-confirm fast path and the post-confirm
  // microtask share one place (issue #55). `target` is captured up front because
  // this can run in a later microtask, after event.target has been reset.
  #proceed(target, action, params, debounce, throttle, optimistic, busy) {
    // Lifecycle veto point (issue #79): one cancelable reactive:before-dispatch
    // per user gesture — post-preventDefault, post-confirm, PRE-debounce (and
    // PRE-throttle, the same timing). event.preventDefault() skips the
    // debounce/throttle AND the enqueue entirely (nothing is scheduled).
    // retry() re-enters the queue directly, so this does NOT refire on a retry.
    // detail.params are the trigger's explicit params; sibling fields are
    // collected later, at send time.
    const before = this.#emit("reactive:before-dispatch", {
      action,
      params: this.#parseParams(params),
      element: this.element,
    }, { cancelable: true })
    if (before.defaultPrevented) return

    // Debounced trigger (e.g. on(:update, event: "input", debounce: 300)):
    // coalesce rapid events into ONE round trip after a quiet period, instead of
    // one POST per keystroke (issue #17). A blur flushes a pending dispatch.
    // The optimistic hint (issue #98) and the busy state (issue #181) ride to
    // the flush too, so they apply ONCE per enqueue — a debounced input must not
    // flap toggle_class per keystroke, and its element must NOT be disabled
    // during the quiet period (that would break typing). Both apply at ENQUEUE.
    const ms = Number(debounce) || 0
    if (ms > 0) return this.#debounceDispatch(target, ms, action, params, optimistic, busy)

    // Throttled trigger (e.g. on(:track, event: "scroll", window: true,
    // throttle: 250), issue #80): LEADING-EDGE rate limit — fire the first
    // event immediately, drop the rest until the window elapses. debounce and
    // throttle are mutually exclusive (the Ruby on() raises on both).
    const throttleMs = Number(throttle) || 0
    if (throttleMs > 0) return this.#throttleDispatch(target, throttleMs, action, params, optimistic, busy)

    return this.#enqueue(action, params, optimistic, target, busy)
  }

  // Apply the optimistic hint ONCE (recording its inverse) and chain the round
  // trip, threading that inverse onto THIS queued request so the serialized
  // per-controller queue reverts the RIGHT request's hint on failure (issue
  // #98). Applying here — the single flush/enqueue point every path funnels
  // through — is what makes a hint apply once per enqueue, not per raw dispatch.
  //
  // The busy state (issue #181) applies here too, for the same reason: enqueue
  // is the moment the request is committed to the queue, so the always-on busy
  // vocabulary (data-reactive-busy on the trigger + root, aria-busy via a pending
  // counter, busy_on scoping) and the busy hint (disable + class + text swap)
  // cover the WHOLE pending window — queue wait included — not just the fetch. It
  // returns a `settle` closure that #perform runs in its finally (success OR
  // failure), guarded so a morph-replaced trigger is never clobbered.
  #enqueue(action, params, optimistic, target, busy) {
    const inverse = this.#applyOptimistic(optimistic, target)
    const settle = this.#applyBusy(action, target, busy)
    // Debug-only teaching aid (issue #181): if optimistic: { hide: true } is used
    // for instant-delete but the reply RE-RENDERS the element (bringing it back),
    // that hint was pointless — the developer likely wanted reply.remove. Capture
    // the hidden nodes now; the success path re-checks the OBSERVED DOM after the
    // morph (never inferred from the verb) and warns if any came back visible.
    const resurrect = this.#debugEnabled() ? this.#buildResurrectionCheck(optimistic, target) : null
    this.queue = (this.queue ?? Promise.resolve())
      .then(() => this.#perform(action, params, inverse, settle, resurrect))
    return this.queue
  }

  // Snapshot the elements an optimistic hide: targeted (the trigger, or the `to:`
  // selector) so the success path can detect a resurrection. Returns null unless
  // a hide: hint is present — nothing else can be "resurrected".
  #buildResurrectionCheck(optimistic, target) {
    if (!optimistic?.hide) return null
    const hidden = this.#hintTargets(optimistic, target)
    if (!hidden.length) return null
    return () => {
      const back = hidden.filter((el) => el.isConnected && !el.hidden)
      if (!back.length) return
      console.warn(
        "[phlex-reactive] optimistic: { hide: true } was undone by the reply's re-render — " +
          "the element is visible again. For an instant delete, return reply.remove so the " +
          "server removes it; otherwise the hide only flashes.",
        back,
      )
    }
  }

  // Reset a per-element timer; only enqueue the round trip after `ms` of quiet.
  // Also flush immediately on blur so leaving the field never drops the last
  // edit (a long debounce shouldn't swallow a value the user tabbed away from).
  #debounceDispatch(target, ms, action, params, optimistic, busy) {
    this.#clearDebounce(target)

    const flush = () => {
      this.#clearDebounce(target)
      this.#enqueue(action, params, optimistic, target, busy)
    }
    const timer = setTimeout(flush, ms)
    target?.addEventListener?.("blur", flush, { once: true })
    this.#debounceTimers.set(target, { timer, flush })
  }

  #clearDebounce(target) {
    const pending = this.#debounceTimers.get(target)
    if (!pending) return
    clearTimeout(pending.timer)
    target?.removeEventListener?.("blur", pending.flush)
    this.#debounceTimers.delete(target)
  }

  // Clear every pending debounce timer (used on disconnect). Reuses
  // #clearDebounce so all timer/listener teardown stays in one place. Snapshot
  // the keys first — #clearDebounce mutates the map as it goes.
  #clearAllDebounces() {
    for (const target of [...this.#debounceTimers.keys()]) this.#clearDebounce(target)
  }

  // Leading-edge throttle (issue #80), mirroring #debounceDispatch: the FIRST
  // event fires immediately; a suppression timer then drops further events
  // until the window elapses (no trailing fire — dropped, not queued). Timers
  // are keyed on action + target, NOT target alone: window-bound scroll/resize
  // events all share event.target === document, so two window-bound triggers
  // on one component would otherwise collide on one timer.
  #throttleDispatch(target, ms, action, params, optimistic, busy) {
    const timers = this.#throttleTimers.get(target) ?? new Map()
    if (timers.has(action)) return // inside the window — suppress

    const timer = setTimeout(() => {
      timers.delete(action)
      if (timers.size === 0) this.#throttleTimers.delete(target)
    }, ms)
    timers.set(action, timer)
    this.#throttleTimers.set(target, timers)
    return this.#enqueue(action, params, optimistic, target, busy) // leading edge: fire NOW
  }

  // Clear every throttle suppression timer (used on disconnect, alongside
  // #clearAllDebounces) so nothing outlives the element.
  #clearAllThrottles() {
    for (const timers of this.#throttleTimers.values()) {
      for (const timer of timers.values()) clearTimeout(timer)
    }
    this.#throttleTimers.clear()
  }

  // Raw-dispatch a lifecycle CustomEvent (issue #79). Deliberately NOT
  // Stimulus's this.dispatch() helper — that name is SHADOWED by this
  // controller's own dispatch(event) action method. Bubbling + composed so a
  // page-level listener (or `data-action="reactive:error->toast#show"` on an
  // ancestor) hears it. After a plain (non-morph) replace this.element is a
  // DETACHED node — a bubbling event on it never reaches document listeners —
  // so fall back to dispatching on document itself.
  #emit(name, detail, { cancelable = false } = {}) {
    const event = new CustomEvent(name, { bubbles: true, composed: true, cancelable, detail })
    const root = this.element.isConnected ? this.element : document
    root.dispatchEvent(event)
    return event
  }

  // reactive:error detail: { action, params, kind, status?, body?, retry }.
  // `params` are the FULL params that were sent (collected fields + explicit
  // trigger params). retry() re-enters the request queue with the ORIGINAL raw
  // trigger params, so #perform re-reads the freshest token and RE-COLLECTS the
  // sibling fields — nothing stale is replayed. It does not refire
  // reactive:before-dispatch (one veto per user gesture), and it no-ops with a
  // warning once the root has left the DOM (retrying against a detached
  // element would post a stale token into nowhere).
  #emitError(action, rawParams, sentParams, extra) {
    const retry = () => {
      if (!this.element.isConnected) {
        console.warn("[phlex-reactive] retry() ignored — the reactive root left the DOM")
        return
      }
      return this.#enqueue(action, rawParams)
    }
    this.#emit("reactive:error", { action, params: sentParams, ...extra, retry })
  }

  // Mark the reactive root as errored (issue #100) with the failure kind, so an
  // app can style it purely in CSS ([data-reactive-error] { … }) with zero JS.
  // Guarded — a plain replace may have detached the root before the failure lands.
  #markError(kind) {
    if (this.element?.isConnected === false) return
    this.element?.setAttribute?.("data-reactive-error", kind)
  }

  // Clear the failure marker on the next successful apply (issue #100).
  #clearError() {
    this.element?.removeAttribute?.("data-reactive-error")
  }

  // Offline fallback (issue #100): a network failure reached no server, so there
  // is no body to render. Clone the content of a server-rendered
  // <template data-reactive-error-flash> into the flash region so the user still
  // sees SOMETHING. The template is app-authored (trusted) — this is a pure
  // deep clone, never client templating of untrusted data. No template, or no
  // flash container, is a silent no-op (a page without the opt-in is unchanged).
  #renderNetworkFallback() {
    const template = document.querySelector("[data-reactive-error-flash]")
    if (!template?.content) return
    // The flash region is the host-app container Response#flash targets. Its id
    // defaults to "flash" (Phlex::Reactive.flash_target); an app that customized
    // it can point the fallback at the same node by putting the template's
    // data-reactive-error-flash value there — but the common case is #flash.
    const targetId = template.getAttribute("data-reactive-error-flash") || "flash"
    const region = document.getElementById(targetId)
    if (!region) return
    region.appendChild(template.content.cloneNode(true))
  }

  // Latency simulator (issue #102): if enableLatencySim(ms) stored a delay in
  // sessionStorage, await it before the fetch so the busy window (already open
  // since enqueue) is actually visible on localhost. Reads the key LIVE per
  // request — like the CSRF token — so toggling the sim mid-session takes effect
  // on the very next action without a reload. A missing sessionStorage, an absent
  // key, or a non-positive/NaN value resolves immediately (no timer, no delay) —
  // the whole feature is inert for any app that never opts in. Warns ONCE while
  // active (module-level guard), not once per request.
  #maybeSimulateLatency() {
    if (typeof sessionStorage === "undefined") return Promise.resolve()
    const ms = Number(sessionStorage.getItem(LATENCY_KEY))
    if (!Number.isFinite(ms) || ms <= 0) return Promise.resolve()
    if (!latencyBannerShown) {
      latencyBannerShown = true
      console.warn(
        `[phlex-reactive] latency simulator ACTIVE — every action is delayed by ${ms}ms. ` +
          "Call PhlexReactive.disableLatencySim() (or clear sessionStorage) to turn it off.",
      )
    }
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  // Client debug mode (issue #108) — the "devtools-lite" lens. On when the Ruby
  // reactive_attrs stamped data-reactive-debug="true" (Phlex::Reactive.debug).
  // Read live (a single getAttribute) so the whole feature is inert for any app
  // that never opts in: OFF → this returns false and #perform builds no debug
  // object, parses no response, and logs nothing (the "zero cost when off"
  // invariant — one nil-check per dispatch). Guarded for a stub root with no
  // getAttribute (unit harnesses) so it degrades to off, never throwing.
  #debugEnabled() {
    return this.element?.getAttribute?.("data-reactive-debug") === "true"
  }

  // A monotonic timestamp for the round-trip duration (ms). performance.now is
  // monotonic (immune to a wall-clock adjustment mid-request); Date.now is the
  // fallback for an exotic environment without it. ONLY called on the debug path,
  // so it costs nothing when debug is off.
  #debugNow() {
    return typeof performance !== "undefined" && typeof performance.now === "function"
      ? performance.now()
      : Date.now()
  }

  // Parse a turbo-stream response's action + target pairs for the debug trace,
  // from the body text #perform ALREADY read (never a re-fetch). NAMES only — the
  // <template> contents (rendered HTML, the fresh token) are deliberately not
  // touched. A non-turbo-stream / empty body yields [] (nothing to report).
  #debugStreams(body) {
    if (!body) return []
    const streams = []
    const re = /<turbo-stream\b([^>]*)>/g
    let match
    while ((match = re.exec(body)) !== null) {
      const attrs = match[1]
      const action = attrs.match(/\baction="([^"]*)"/)?.[1] ?? "?"
      const target = attrs.match(/\btarget="([^"]*)"/)?.[1]
      streams.push(target ? `${action} → #${target}` : action)
    }
    return streams
  }

  // console.group ONE dispatch (issue #108). Carries NAMES + outcomes ONLY — the
  // signed token VALUE and every field/param VALUE are deliberately absent (they
  // may be sensitive; the whole point is observability without leaking data). The
  // caller passes the info it already holds so nothing is recomputed or re-fetched:
  //   { action, paramNames, fieldNames, encoding, status, streams, tokenRefreshed, ms }
  // `console.groupCollapsed` keeps the console tidy (one collapsed line per action).
  #logDispatch(info) {
    const { action, status, ms } = info
    // The client can't name the component CLASS (it's inside the signed, opaque
    // token — never decoded here), but the root's id is the stable client-side
    // handle (e.g. #todo_42), so the header reads `reactive #todo_42 rename → …`.
    const who = this.element?.id ? `#${this.element.id} ` : ""
    const header = `reactive ${who}${action} → ${status ?? "—"} (${Math.round(ms)}ms)`
    /* eslint-disable no-console */
    console.groupCollapsed(header)
    console.log(`params: [${info.paramNames.join(", ")}] + collected: [${info.fieldNames.join(", ")}]`)
    console.log(`encoding: ${info.encoding}`)
    if (info.streams.length) console.log(`streams: ${info.streams.join("   ")}`)
    console.log(`token: ${info.tokenRefreshed ? "refreshed ✓" : "unchanged"}`)
    console.groupEnd()
    /* eslint-enable no-console */
  }

  async #perform(action, params, inverse, settle, resurrect) {
    // Auto-collect named field values inside this component so a button-
    // triggered action still receives sibling inputs (Livewire-style), plus any
    // chosen file inputs in the SAME walk. Explicit params
    // (data-reactive-params-param) win over collected fields.
    const { fields, files } = this.#collectFields()
    // Parse the explicit trigger params ONCE — reused below for allParams and, on
    // the debug path, for the params-only name list (so the trace can show
    // `params: [...]` distinct from the collected `+ collected: [...]`). #parseParams
    // is pure (a fresh object from a JSON string, or the same object by reference
    // when already parsed); allParams spreads a COPY and nothing mutates parsedParams
    // downstream (JSON.stringify / #buildFormData read allParams, a new object).
    const parsedParams = this.#parseParams(params)
    const allParams = { ...fields, ...parsedParams }
    const token = this.#currentToken

    // File/multipart path (issue #34): if THIS root has a populated
    // <input type="file">, the action can't be JSON (JSON.stringify drops the
    // File). Send FormData instead — token + act + scalar params as fields, each
    // chosen file appended. The morph/token machinery downstream is identical;
    // only the request ENCODING differs when files are present.
    const multipart = files.length > 0
    const body = multipart
      ? this.#buildFormData(token, action, allParams, files)
      : JSON.stringify({ token, act: action, params: allParams })

    // Client debug mode (issue #108): build the trace object ONLY when debug is on
    // (one nil-check otherwise — zero cost off). It carries NAMES only: the
    // explicit trigger param names and the collected sibling field names, split so
    // the group shows `params: [...] + collected: [...]`. status/streams/
    // tokenRefreshed are filled in at the branch that knows them; the group is
    // emitted once in the finally so EVERY exit (success or any failure) logs.
    const debug = this.#debugEnabled()
      ? {
          action,
          paramNames: Object.keys(parsedParams),
          fieldNames: Object.keys(fields),
          encoding: multipart ? "multipart" : "json",
          status: null,
          streams: [],
          tokenRefreshed: false,
          started: this.#debugNow(),
        }
      : null

    // aria-busy on the root is now driven by the loading pending counter
    // (#applyLoading, applied at ENQUEUE so it covers the queue wait too), not
    // set here. #settleLoading in the finally clears it — see #enqueue.

    // Latency simulator (issue #102): the busy window (aria-busy + loading state)
    // is already applied at enqueue, so awaiting the configured delay HERE — after
    // that window opened and before the fetch — is what makes it visible on
    // localhost. A null/absent/non-positive sessionStorage key is a no-op (zero
    // production surface), so this line vanishes for any app that never opts in.
    await this.#maybeSimulateLatency()

    try {
      // Offline gate (issue #101), authoritative at the NETWORK BOUNDARY (send
      // time), not at enqueue. A click can enqueue while online and reach here
      // after going offline (a debounced/queued request, a rapid transition) —
      // gating in #perform makes the kind consistently "offline" for that whole
      // condition instead of leaking through as a "network" fetch throw. The
      // fetch never fires, so the edit is not half-sent; the finally still runs
      // (settle clears loading), the optimistic hint reverts, and retry() (which
      // re-enters #perform) re-checks and sends once back online.
      if (navigator.onLine === false) {
        this.#revertOptimistic(inverse)
        this.#markError("offline")
        this.#emitError(action, params, allParams, { kind: "offline" })
        return
      }

      let response
      try {
        const headers = {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.#csrfToken(),
        }
        // For JSON we declare the content type; for multipart we must NOT — the
        // browser sets `multipart/form-data; boundary=…` itself, and overriding it
        // would strip the boundary and corrupt the body server-side.
        if (!multipart) headers["Content-Type"] = "application/json"
        // Send the pgbus SSE connection id (if subscribed) so the server can
        // exclude this connection from its own broadcast echo — the actor
        // already gets the action's HTTP response. Harmless without pgbus.
        const connectionId = this.#connectionId()
        if (connectionId) headers["X-Pgbus-Connection"] = connectionId

        // ONLY `fetch` itself is the network boundary — offline, DNS, a reset
        // connection. Everything below this inner try (reading the body,
        // extracting the token, handing streams to Turbo) runs AFTER the
        // server already processed the mutation, so none of it belongs in the
        // `kind: "network"` / retriable bucket (CodeRabbit review on #89): if
        // renderStreamMessage throws, retry()ing would re-POST an action the
        // server already completed — see the outer catch below. (NOT a
        // reactive:applied LISTENER throwing — per the DOM spec, dispatchEvent
        // never propagates a listener's exception back to its caller, so that
        // case can't reach this catch at all; verified in the JS test suite.)
        response = await fetch(this.#actionPath(), {
          method: "POST",
          headers,
          body,
          credentials: "same-origin",
          // Bound the request (issue #101): a server that never answers used to
          // wedge this.queue forever (the finally that clears aria-busy/loading
          // never ran). AbortSignal.timeout(ms) aborts the fetch after the
          // configured window; the abort surfaces in this catch as a
          // DOMException named "TimeoutError" (see the branch below).
          signal: AbortSignal.timeout(this.#timeoutMs()),
        })
      } catch (error) {
        console.error("[phlex-reactive] action error", error)
        this.#revertOptimistic(inverse)
        // AbortSignal.timeout() rejects with a DOMException named "TimeoutError"
        // (a manual AbortController.abort() would be "AbortError" — we don't use
        // one, but accept it too for robustness). A timeout is NOT "offline":
        // the request left and the server didn't answer in time; connectivity is
        // unknown. So do NOT clone the offline-fallback template or mark network
        // — just fire kind:"timeout" (retriable). The queue still advances
        // (#perform returns, never rejects), so the hung request un-wedges it.
        if (error?.name === "TimeoutError" || error?.name === "AbortError") {
          this.#markError("timeout")
          this.#emitError(action, params, allParams, { kind: "timeout" })
          return
        }
        // No server reached — nothing to render (issue #100). Clone a
        // server-rendered <template data-reactive-error-flash> into the flash
        // region as an offline fallback. The template is rendered by the app
        // (trusted), so this is a pure clone — no client templating of data.
        this.#renderNetworkFallback()
        this.#markError("network")
        this.#emitError(action, params, allParams, { kind: "network" })
        return
      }

      // Debug (issue #108): the server answered — record the status for the trace
      // now, so every response branch below (redirected/http/content-type/ok) logs
      // it. The transport-failure branches above return before here (they have no
      // status); their group still fires from the finally with status null → "—".
      if (debug) debug.status = response.status

      if (response.redirected) {
        console.error("[phlex-reactive] action was redirected (auth/CSRF?) — no update applied")
        this.#revertOptimistic(inverse)
        this.#markError("redirected")
        this.#emitError(action, params, allParams, { kind: "redirected", status: response.status })
        return
      }
      if (!response.ok) {
        const errorBody = await response.text()
        console.error(`[phlex-reactive] action failed: HTTP ${response.status}`, errorBody)
        this.#revertOptimistic(inverse)
        // Render a non-OK turbo-stream body so a server-rendered error flash
        // (an error_flash rescue, or a status: :unprocessable_entity validation
        // reply from a plain controller) is actually SHOWN — instead of being
        // read only for the console (issue #100). #extractToken is run as usual;
        // it NO-OPS when no stream re-renders our id, so a 400 InvalidToken body
        // never refreshes the held identity token (which is not a nonce and stays
        // retry-valid — do not "fix" that). A non-turbo-stream body is left to the
        // console.error above (an HTML error page must not be handed to Turbo).
        if ((response.headers.get("Content-Type") || "").includes("turbo-stream")) {
          const fresh = this.#extractToken(errorBody)
          this.#currentToken = fresh ?? this.#currentToken
          if (debug) this.#debugRecordBody(debug, errorBody, fresh)
          window.Turbo.renderStreamMessage(errorBody)
        }
        this.#markError("http")
        this.#emitError(action, params, allParams, { kind: "http", status: response.status, body: errorBody })
        return
      }

      const contentType = response.headers.get("Content-Type") || ""
      if (!contentType.includes("turbo-stream")) {
        console.error(`[phlex-reactive] expected a turbo-stream, got "${contentType}" — no update applied`)
        this.#revertOptimistic(inverse)
        this.#markError("content-type")
        this.#emitError(action, params, allParams, { kind: "content-type", status: response.status })
        return
      }

      const html = await response.text()
      // Capture the new token from the response synchronously, so the next
      // queued request uses it without waiting for the async DOM morph.
      const fresh = this.#extractToken(html)
      this.#currentToken = fresh ?? this.#currentToken
      // Debug (issue #108): record the stream actions/targets + whether a refresh
      // arrived, from the body we JUST read (reuse — no second text() read). Never
      // the token or template contents.
      if (debug) this.#debugRecordBody(debug, html, fresh)
      // Turbo applies the <turbo-stream> ops by id. A plain replace is an
      // outerHTML swap (focus on the replaced subtree is lost); a method="morph"
      // replace (Response.morph) or an update morphs in place, preserving the
      // focused input + caret on unchanged nodes — see issue #28.
      window.Turbo.renderStreamMessage(html)
      // Debug-only (issue #181): the morph may apply a microtask later, so check
      // the resurrected-hide case AFTER it lands. Off the debug path, resurrect is
      // null — zero cost.
      if (resurrect) queueMicrotask(resurrect)
      // A successful apply CLEARS any prior failure marker (issue #100), so
      // error-driven CSS on the root (a red border, a shake) resets on recovery.
      this.#clearError()
      // Lifecycle hook (issue #79): the streams were HANDED TO Turbo — a
      // renderStreamMessage applies asynchronously, so the DOM mutation may
      // complete a tick later. Apps needing post-morph timing listen to Turbo's
      // own events; this one is for "the action round trip succeeded".
      this.#emit("reactive:applied", { action, params: allParams, html })
    } catch (error) {
      // The server already processed this action successfully (we're past the
      // fetch) — a throw here is a CLIENT-side apply failure (a malformed
      // response, a broken Turbo render — NOT a reactive:applied listener
      // throw, which dispatchEvent never propagates here), not a transport
      // failure. kind: "apply" carries NO retry() — retrying would re-POST an
      // action the server already completed.
      console.error("[phlex-reactive] action error", error)
      this.#revertOptimistic(inverse)
      this.#emit("reactive:error", { action, params: allParams, kind: "apply" })
    } finally {
      // Settle the loading state (issue #99): decrement the pending counter,
      // drop the trigger's/root's busy tokens, restore disabled/text/class —
      // guarded so a morph-replaced trigger is never clobbered. Runs on EVERY
      // exit (success, every failure branch, or an apply throw).
      settle?.()
      // Debug (issue #108): emit the group here so EVERY exit path logs exactly
      // once — success, any transport/response failure, or an apply throw. Null
      // when debug is off (zero cost). The round-trip ms is measured now, at the
      // finally, so it spans the whole #perform (fetch + apply) regardless of exit.
      if (debug) this.#logDispatch({ ...debug, ms: this.#debugNow() - debug.started })
    }
  }

  // Debug (issue #108): fold the response body #perform already read into the
  // trace — the stream action/target pairs and whether a token refresh arrived
  // (a boolean; the token VALUE is intentionally not stored). Shared by the
  // success and the non-OK-turbo-stream branches so both log the same shape.
  #debugRecordBody(debug, body, freshToken) {
    debug.streams = this.#debugStreams(body)
    debug.tokenRefreshed = freshToken != null
  }

  get #currentToken() {
    return this.#tokenCache ?? this.tokenValue
  }

  set #currentToken(value) {
    this.#tokenCache = value
  }

  // Read the next token for THIS controller — the one that re-renders THIS
  // element's id, never just the first token in the body (issue #46). On a
  // collection of REACTIVE rows the prepended/appended ROW carries its OWN
  // data-reactive-token-value and it sorts FIRST in the response; the list's own
  // fresh token rides a trailing `reactive:token` stream targeting the container.
  // Grabbing the first match stored the ROW's token, so the list's SECOND
  // dispatch sent a row token → failed verification → add-once-only. This mirrors
  // the server's carries_token_for? (#44): a stream carries OUR token only when it
  // RE-RENDERS our id (reactive:token / replace / update of `this.element.id`) —
  // append/prepend insert children and never count. Returns undefined when no
  // stream re-renders our id, so #currentToken keeps its existing value.
  #extractToken(html) {
    const id = this.element.id
    if (!id) {
      // No id to self-match (shouldn't happen for a reactive root). Fall back to
      // the legacy first-token behavior so a single-component response still works.
      return html.match(/data-reactive-token-value="([^"]+)"/)?.[1]
    }

    const { token, self } = this.#tokenRegexes(id)

    // The dedicated token-only refresh for THIS element (partial updates / the
    // collection container) — an attribute on the <turbo-stream> itself.
    const tokenStream = html.match(token)
    if (tokenStream) return tokenStream[1]

    // A full self re-render: a replace/update of THIS element whose template root
    // carries the fresh token. Scope the token search to that one stream so a
    // sibling/child token elsewhere in the body can't leak in.
    const selfStream = html.match(self)
    if (selfStream) return selfStream[1].match(/data-reactive-token-value="([^"]+)"/)?.[1]

    // Nothing re-rendered our id — keep the current token.
    return undefined
  }

  // The two per-id RegExps #extractToken uses to self-match this element's next
  // token (issue #118). `this.element.id` is page-stable, so these are compiled
  // ONCE and reused across every response — instead of allocating two fresh
  // RegExps per round trip. The memo is KEYED ON THE ID and rebuilt when it
  // changes: a re-render that re-identifies the root must scan for the NEW target,
  // never the stale one (or the token would freeze — see the id-change bun test).
  // The PATTERNS are byte-identical to the pre-memo inline literals; only their
  // allocation moved.
  #tokenRegexes(id) {
    const cache = this.#tokenRegexCache
    if (cache && cache.id === id) return cache
    const escaped = escapeRegExp(id)
    return (this.#tokenRegexCache = {
      id,
      token: new RegExp(
        `<turbo-stream\\b[^>]*\\baction="reactive:token"[^>]*\\btarget="${escaped}"[^>]*\\bdata-reactive-token-value="([^"]+)"`,
      ),
      self: new RegExp(
        `<turbo-stream\\b[^>]*\\baction="(?:replace|update)"[^>]*\\btarget="${escaped}"[^>]*>([\\s\\S]*?)</turbo-stream>`,
      ),
    })
  }

  // True when `el` is collected by THIS reactive root and not by a nested one.
  // A reactive component can be rendered inside another (both are
  // data-controller="reactive" roots). querySelectorAll() descends into nested
  // roots, so without this guard an outer action would sweep the inner roots'
  // inputs into its own params (issue #15). An element belongs to this root iff
  // its nearest [data-controller~="reactive"] ancestor is this.element.
  #ownsField(el) {
    return el.closest('[data-controller~="reactive"]') === this.element
  }

  // A per-op ownership PREDICATE — the issue #117 fast path over issue #15
  // scoping. #ownsField answers "is this element mine, not a nested reactive
  // root's" with a per-element closest() walk; on a wide form or every keystroke
  // that walk runs per matched field. This hoists the DECISION to once per op.
  //
  // HYBRID GATE — closest() stays the source of truth; the nested-root query only
  // decides whether the fast path is SAFE:
  //   * Fast path (overwhelmingly common): this root contains NO nested reactive
  //     roots, so every element the caller's querySelectorAll returned is already
  //     a direct descendant of this.element with no intervening reactive root —
  //     it is ours. Return a constant-true predicate and skip the per-field
  //     closest() walk entirely. That is the whole win.
  //   * Nested case: fall back to the UNCHANGED #ownsField closest() check, so
  //     scoping is byte-identical to before. We deliberately do NOT use
  //     contains() here — the closest() form needs no node to implement
  //     contains(), and on a real DOM the two agree for a descendant of
  //     this.element (el.closest('[data-controller~="reactive"]') === this.element
  //     iff no nested reactive-root descendant contains el).
  //
  // Computed ONCE per dispatch-scoped op (per #collectFields call, per recompute,
  // per #listnavOptions) and NEVER stored on the instance — a morph replaces
  // nodes, so a cached predicate would close over stale roots.
  #ownershipFilter() {
    const nested = this.element.querySelectorAll('[data-controller~="reactive"]')
    if (nested.length === 0) return () => true
    return (el) => this.#ownsField(el)
  }

  // One walk over THIS root's named controls (not a nested reactive root's),
  // returning both the scalar `fields` and any chosen `files`. The ownership
  // predicate is hoisted ONCE (issue #117) via #ownershipFilter — in the common
  // no-nested-root case it is a constant true, so we skip a closest() walk per
  // field. A file input's `.value` is the useless "C:\fakepath\…" string, never a
  // scalar — so its chosen files are collected separately (honoring `multiple`)
  // and it adds no phantom blank value (issue #34). An empty `files` keeps the
  // JSON path.
  #collectFields() {
    const fields = {}
    const files = []
    const owns = this.#ownershipFilter() // compute ONCE per dispatch (issue #117)
    this.element.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (!owns(field)) return
      if (field.type === "file") {
        // Carry the input's `multiple` flag so #buildFormData keeps the array
        // shape (params[name][]) even when the user picked exactly one file —
        // otherwise a [:file] schema would see a lone scalar upload and drop it.
        for (const file of field.files ?? []) files.push({ name: field.name, file, multiple: field.multiple })
      } else if (field.type === "checkbox") {
        fields[field.name] = field.checked
      } else if (field.type === "radio") {
        if (field.checked) fields[field.name] = field.value
      } else {
        fields[field.name] = field.value
      }
    })
    // Named rich-text / custom editors (lexxy-editor, trix-editor) and bare
    // [contenteditable]. These aren't input/select/textarea, so the query above
    // skips them — without this, a reactive save posts an empty value and
    // silently wipes the field (issue #8). Read whatever the element exposes:
    // a custom editor's serialized `.value`, else its contenteditable text.
    // Only fill a name the standard controls left absent or empty, so a synced
    // hidden input (e.g. Trix mirrors into one) still wins when populated.
    this.element
      .querySelectorAll("[name]:is(lexxy-editor, trix-editor, [contenteditable=''], [contenteditable=true], [contenteditable=plaintext-only])")
      .forEach((el) => {
        if (!owns(el)) return // reuse the SAME hoisted predicate (nested reactive root — issue #15)
        // A plain element (e.g. a <div contenteditable>) has no `name` IDL
        // property — only the attribute — so read getAttribute, not el.name.
        const name = el.getAttribute("name")
        if (!name) return
        const existing = fields[name]
        if (existing == null || existing === "") {
          fields[name] = el.value ?? el.textContent ?? el.innerHTML ?? ""
        }
      })
    return { fields, files }
  }

  // Re-compute the dirty flag for EVERY field this root owns in one pass (issue
  // #103), then reflect the total onto the root. Called on an owned field's input
  // (trackDirty), on connect (baseline seed), and after a turbo:morph-element
  // re-render (fresh default* attrs). dirty = current ≠ the DOM's own default:
  //   checkbox/radio → checked  !== defaultChecked
  //   select         → some option.selected !== option.defaultSelected
  //   else           → value    !== defaultValue
  // A full pass (not per-target) is REQUIRED: a radio group's previously-checked
  // radio flips to checked=false with NO input event, so per-target toggling
  // would leave its flag stale. File inputs are skipped — a file has no server
  // default baseline. Per-dirty-field data-reactive-dirty="true" ("true" STRING,
  // not a valueless boolean attr — mirrors the on() flag convention); the root
  // carries data-reactive-dirty="<count>" and DROPS the attr at zero, so
  // `[data-reactive-dirty]` styles the whole form and `[data-reactive-dirty]`
  // on a field styles just the changed control — both pure CSS, zero JS.
  #scanDirty() {
    // Runs at bootstrap (the connect baseline seed) as well as on input/morph, so
    // it must never throw — degrade to a no-op if the root can't be queried (a real
    // reactive root always can; this guards minimal/test element stubs).
    if (typeof this.element?.querySelectorAll !== "function") return

    let count = 0
    this.element.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (!this.#ownsField(field)) return // skip a nested reactive root's fields (issue #15)
      if (field.type === "file") return // no server default baseline to diff against

      if (this.#fieldDirty(field)) {
        field.setAttribute("data-reactive-dirty", "true")
        count++
      } else {
        field.removeAttribute("data-reactive-dirty")
      }
    })

    if (count > 0) this.element.setAttribute("data-reactive-dirty", String(count))
    else this.element.removeAttribute("data-reactive-dirty")
  }

  // Whether a single owned control differs from its server-rendered default.
  #fieldDirty(field) {
    if (field.type === "checkbox" || field.type === "radio") {
      return field.checked !== field.defaultChecked
    }
    if (field.tag === "select" || field.options) {
      // Any option whose selected state diverges from its defaultSelected. Guard
      // for a stub/absent options list (degrade to clean).
      return Array.from(field.options ?? []).some((o) => o.selected !== o.defaultSelected)
    }
    return field.value !== field.defaultValue
  }

  // The live dirty-field count, re-derived from the DOM (never a cached snapshot)
  // — the source of truth for the warn_unsaved guard's gate.
  #dirtyCount() {
    const raw = this.element.getAttribute?.("data-reactive-dirty")
    const n = Number(raw)
    return Number.isFinite(n) && n > 0 ? n : 0
  }

  // Arm the navigate-away guard (warn_unsaved: true, issue #103). beforeunload
  // blocks a real browser unload; turbo:before-visit blocks a Turbo in-app
  // navigation (it does NOT fire on restoration visits — the documented gap).
  // Both read the LIVE dirty count, so a clean form never blocks. Handlers are
  // stored so disconnect() removes exactly them.
  #armUnsavedGuard() {
    if (typeof window === "undefined" || typeof window.addEventListener !== "function") return

    this.#boundBeforeUnload = (event) => {
      if (this.#dirtyCount() === 0) return undefined
      // The spec dance: preventDefault + a truthy returnValue triggers the native
      // "leave site?" prompt. The string is legacy (modern browsers show their own
      // copy) but must be non-empty/truthy to arm the dialog.
      event.preventDefault()
      event.returnValue = "You have unsaved changes."
      return event.returnValue
    }
    this.#boundBeforeVisit = (event) => {
      if (this.#dirtyCount() === 0) return
      const ok = typeof window.confirm === "function" ? window.confirm("You have unsaved changes. Leave anyway?") : true
      if (!ok) event.preventDefault?.()
    }

    window.addEventListener("beforeunload", this.#boundBeforeUnload)
    window.addEventListener("turbo:before-visit", this.#boundBeforeVisit)
  }

  // Remove the dirty-tracking listeners on disconnect (Turbo morph/navigation) so
  // a morph re-scan or a navigate-away guard never runs against a detached root.
  #teardownDirtyTracking() {
    if (this.#boundScanDirty) {
      this.element.removeEventListener?.("turbo:morph-element", this.#boundScanDirty)
      this.#boundScanDirty = undefined
    }
    if (typeof window !== "undefined" && typeof window.removeEventListener === "function") {
      if (this.#boundBeforeUnload) window.removeEventListener("beforeunload", this.#boundBeforeUnload)
      if (this.#boundBeforeVisit) window.removeEventListener("turbo:before-visit", this.#boundBeforeVisit)
    }
    this.#boundBeforeUnload = undefined
    this.#boundBeforeVisit = undefined
  }

  // Whether this root owns a show binding (issue #161) or declares cross-root
  // show targets (issue #164) — the connect() gate, so a component with
  // neither pays only this probe (the #dirtyTrackingEnabled precedent). A
  // NESTED root's bindings don't count: its own controller instance syncs them
  // (issue #15 ownership). The targets attr is checked FIRST — one
  // getAttribute, cheaper than the binding walk.
  #showSyncEnabled() {
    if (this.element.getAttribute?.("data-reactive-show-targets")) return true
    // Single-field bindings carry -field; compound all:/any: bindings (issue
    // #176) carry data-reactive-show and have NO single controlling field, so
    // both selectors gate the sync.
    const nodes = this.element.querySelectorAll?.(SHOW_BINDING_SELECTOR) ?? []
    for (const el of nodes) if (this.#ownsField(el)) return true
    return false
  }

  // Re-evaluate every OWNED show binding in one pass (issue #161): read the
  // controlling field's current value, evaluate the declared literal predicate,
  // toggle `hidden`. A full pass (not per-target) for the same reason as
  // #scanDirty — a radio group's deselected radio fires no event — and because
  // several bindings can hang off one field (the value read is memoized per
  // pass). A binding whose field can't be resolved, or whose predicate is
  // malformed, leaves visibility ALONE — a bad binding must never break or
  // blank the page (client-side default-deny).
  #syncShow() {
    if (typeof this.element?.querySelectorAll !== "function") return

    const owns = this.#ownershipFilter()
    const scope = this.element.getAttribute?.("data-reactive-scope") || null
    const values = new Map()
    // A memoized resolver shared by every binding in this pass — a field driving
    // several bindings (and several DNF terms) reads exactly once. Scope-aware:
    // a bare field `director` resolves as `[name="scope[director]"]` (issue #180).
    const fieldValue = (name) => {
      if (!values.has(name)) values.set(name, this.#showFieldValue(name, owns, scope))
      return values.get(name)
    }
    for (const el of this.element.querySelectorAll(SHOW_BINDING_SELECTOR)) {
      if (!owns(el)) continue // a nested root's binding is its own controller's job

      // The 0.10 DNF payload (issue #180): data-reactive-show carries
      // { any: [ [term,…], … ] }. The legacy flat-attr and 0.9.5-compound read
      // arms live in showPayloadMatches/showBindingMatches for deploy overlap.
      const payloadRaw = el.getAttribute("data-reactive-show")
      if (payloadRaw !== null) {
        const match = showPayloadMatches(parseShowCompound(payloadRaw), fieldValue)
        if (match !== null) this.#applyShowVisibility(el, match, owns, scope)
        continue
      }

      // LEGACY flat-attr binding (pre-0.10, deploy overlap — removed in 0.11).
      const name = el.getAttribute("data-reactive-show-field")
      if (!name) continue
      const value = fieldValue(name)
      if (value === null) continue // no owned field with that name — leave it be
      const match = showBindingMatches(el, value)
      if (match === null) continue // malformed predicate — warned + skipped
      this.#applyShowVisibility(el, match, owns, scope)
    }

    // The cross-root pass (issue #164) shares the same owned-field memo, so a
    // field driving both an owned binding and an outside target reads once.
    this.#syncShowTargets(owns, values, scope)
  }

  // Toggle `hidden` (and, when the binding declares data-reactive-show-disable,
  // the `disabled` of every owned named control inside it) from a match result
  // (issue #180). Disabling a hidden section's controls stops them submitting —
  // the stale-value fix. A visible section re-enables them. Controls a nested
  // reactive root owns are left alone (#15 ownership).
  #applyShowVisibility(el, match, owns, scope) {
    el.hidden = !match
    if (el.getAttribute("data-reactive-show-disable") !== "true") return
    if (typeof el.querySelectorAll !== "function") return
    for (const control of el.querySelectorAll("input[name], select[name], textarea[name]")) {
      if (owns(control)) control.disabled = !match
    }
    // The element itself may be a named control (a bare field with a binding).
    if (el.name && owns(el)) el.disabled = !match
  }

  // Apply the declared cross-root show targets (issue #164) — the visibility
  // parallel of #applyComputeMirrors. For each declared field: read the OWNED
  // field's current value (never a nested root's — you can only drive outside
  // visibility from a field this root owns), then for each "#id" → predicate
  // entry: guard the selector id-only (warn-and-skip; the Ruby helper raised
  // at declare time — two-sided default-deny), resolve it DOCUMENT-WIDE, and
  // toggle `hidden`. A target id not on the page is silently skipped (an
  // unrendered tab pane is normal); a malformed predicate warn-skips its one
  // target while siblings still apply. With no map declared this is one
  // getAttribute and out.
  #syncShowTargets(owns, values, scope) {
    const map = this.#parseShowTargets()
    for (const [name, targets] of Object.entries(map)) {
      if (!targets || typeof targets !== "object" || Array.isArray(targets)) continue
      if (!values.has(name)) values.set(name, this.#showFieldValue(name, owns, scope))
      const value = values.get(name)
      if (value === null) continue // no owned field with that name — leave them be
      // Every target's terms share this one field, so a constant resolver folds
      // the group (issue #180): a target's value is a DNF GROUP (terms ANDed).
      const resolve = () => value
      for (const [selector, group] of Object.entries(targets)) {
        if (!guardShowTargetSelector(selector)) continue
        // 0.10 wire: the value is a DNF GROUP (an array of terms, ANDed).
        // LEGACY (0.9.5, deploy overlap — DELETE in 0.11): a flat predicate
        // OBJECT ({ equals/not/in/gte… }) routed through showPredicateMatches.
        let match
        if (Array.isArray(group)) {
          if (group.length === 0) {
            console.warn(`[phlex-reactive] malformed reactive_show_targets group for ${selector} — skipped`)
            continue
          }
          match = group.every((term) => dnfTermMatches(term, resolve))
        } else {
          const legacy = showPredicateMatches(group, value)
          if (legacy === null) {
            console.warn(`[phlex-reactive] malformed reactive_show_targets predicate for ${selector} — skipped`)
            continue
          }
          match = legacy
        }
        for (const node of document.querySelectorAll(selector)) node.hidden = !match
      }
    }
  }

  // The declared cross-root show-target map (issue #164): a JSON object of
  // { field: { "#id": predicate } } from data-reactive-show-targets (emitted
  // by reactive_show_targets on the root). Absent degrades to {}; malformed
  // degrades to {} WITH a warn — never a throw (the #parseComputeMirror
  // contract), but never silent either: the likeliest cause is TWO
  // reactive_show_targets calls on one root, whose JSON strings Phlex `mix`
  // space-joined into an unparseable attr. The warn names the fix.
  #parseShowTargets() {
    const raw = this.element.getAttribute?.("data-reactive-show-targets")
    if (!raw) return {}
    try {
      const parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed
    } catch {
      // fall through to the shared warn below
    }
    console.warn(
      "[phlex-reactive] malformed data-reactive-show-targets — ignored. " +
        "Did two reactive_show_targets calls collide on one root? Declare every field in ONE call: " +
        "reactive_show_targets(mode: { ... }, kind: { ... })"
    )
    return {}
  }

  // The current value of the OWNED field controlling a show binding, as the
  // string the literal predicate compares against. Mirrors #collectFields'
  // per-kind reads: a checkbox reports its checked state ("true"/"false" — its
  // .value is the constant "on", and the checkbox wins over the hidden input
  // Rails pairs with it); a radio group reports the CHECKED radio's value (""
  // when none is); anything else reports .value first-wins. Returns null when
  // no owned field carries the name — the caller then leaves visibility alone.
  #showFieldValue(name, owns, scope) {
    // Scope (issue #180): a bare field `director` under `data-reactive-scope=
    // "form"` resolves as `[name="form[director]"]`. A name already carrying a
    // bracket (a raw wire name the author passed) is used verbatim.
    const domName = scope && !name.includes("[") ? `${scope}[${name}]` : name
    let sawRadio = false
    let first = null
    for (const el of this.element.querySelectorAll(`[name="${domName}"]`)) {
      if (!owns(el)) continue
      if (el.type === "checkbox") return el.checked ? "true" : "false"
      if (el.type === "radio") {
        if (el.checked) return el.value ?? ""
        sawRadio = true
        continue
      }
      first ??= el
    }
    if (first) return first.value ?? ""
    return sawRadio ? "" : null
  }

  // Remove the show-sync listeners on disconnect, so a stray event after a
  // Turbo morph/navigation never re-evaluates against a detached root.
  #teardownShowSync() {
    if (!this.#boundSyncShow) return
    this.element.removeEventListener?.("input", this.#boundSyncShow)
    this.element.removeEventListener?.("change", this.#boundSyncShow)
    this.element.removeEventListener?.("turbo:morph-element", this.#boundSyncShow)
    this.#boundSyncShow = undefined
  }

  // Whether this root declares an option filter (issue #163) — the connect()
  // gate. reactive_filter always emits input + option together, so requiring
  // BOTH also default-denies a half-built hand-authored binding.
  #filterEnabled() {
    return !!(
      this.element.getAttribute?.("data-reactive-filter-input") &&
      this.element.getAttribute?.("data-reactive-filter-option")
    )
  }

  // Whether a delegated input event came from the NAMED filter input (issue
  // #163). Anything else — another field's keystroke, a target without
  // matches() — skips the filter pass (the morph re-sync path bypasses this).
  #filterInputEvent(event) {
    const selector = this.element.getAttribute("data-reactive-filter-input")
    return !!selector && typeof event.target?.matches === "function" && event.target.matches(selector)
  }

  // Re-apply the filter in one pass (issue #163): lowercase the named input's
  // current value, toggle `hidden` on every OWNED option by a substring match
  // against its haystack (data-reactive-filter-text, falling back to the
  // option's own text), collapse any group whose every contained option is
  // hidden, and reveal the empty target at 0 visible. A filtered-out option
  // also loses its listnav highlight so Enter can never pick an invisible row.
  // No owned input → leave visibility ALONE — a binding that can't resolve
  // must never break or blank the page (client-side default-deny). All
  // selectors resolve within this root, skipping nested reactive roots'
  // elements (issue #15 ownership; the predicate is hoisted once per pass).
  #syncFilter() {
    if (typeof this.element?.querySelectorAll !== "function") return
    const inputSelector = this.element.getAttribute("data-reactive-filter-input")
    const optionSelector = this.element.getAttribute("data-reactive-filter-option")
    if (!inputSelector || !optionSelector) return

    const owns = this.#ownershipFilter()
    const input = [...this.element.querySelectorAll(inputSelector)].find(owns)
    if (!input) return

    const query = (input.value ?? "").trim().toLowerCase()
    let visible = 0
    for (const el of this.element.querySelectorAll(optionSelector)) {
      if (!owns(el)) continue // a nested root's option is its own controller's job
      const haystack = (el.getAttribute("data-reactive-filter-text") ?? el.textContent ?? "").toLowerCase()
      const hidden = query !== "" && !haystack.includes(query)
      el.hidden = hidden
      if (hidden) el.removeAttribute("data-reactive-highlighted")
      else visible++
    }

    const groupSelector = this.element.getAttribute("data-reactive-filter-group")
    if (groupSelector) {
      for (const group of this.element.querySelectorAll(groupSelector)) {
        if (!owns(group)) continue
        const contained = [...group.querySelectorAll(optionSelector)].filter(owns)
        // A group with no options isn't this filter's to decide — server state
        // stands (it may be a header the app toggles by other means).
        if (contained.length === 0) continue
        group.hidden = contained.every((el) => el.hidden)
      }
    }

    const emptySelector = this.element.getAttribute("data-reactive-filter-empty")
    if (emptySelector) {
      for (const el of this.element.querySelectorAll(emptySelector)) {
        if (owns(el)) el.hidden = visible > 0
      }
    }
  }

  // Remove the filter-sync listeners on disconnect, so a stray event after a
  // Turbo morph/navigation never re-filters against a detached root.
  #teardownFilterSync() {
    if (!this.#boundSyncFilter) return
    this.element.removeEventListener?.("input", this.#boundSyncFilter)
    this.element.removeEventListener?.("turbo:morph-element", this.#boundSyncFilter)
    this.#boundSyncFilter = undefined
  }

  // Build the multipart body (issue #34). `token`/`act` are flat fields the
  // endpoint reads from params[:token]/params[:act]; scalar params nest under
  // params[<key>] (Rails parses the bracket into params[:params]); each file is
  // appended under params[<name>] (single) — a second file with the same name
  // (a `multiple` picker, several inputs sharing a name) is sent as
  // params[<name>][] so Rails coerces it to an array for a [:file] schema.
  #buildFormData(token, action, params, files) {
    const fd = new FormData()
    fd.append("token", token)
    fd.append("act", action)
    for (const [key, value] of Object.entries(params)) {
      this.#appendField(fd, `params[${key}]`, value)
    }
    const multiNames = this.#multiFileNames(files)
    for (const { name, file, multiple } of files) {
      // params[name][] when the input is `multiple` (array shape even for one
      // file) OR the name repeats across inputs; otherwise a lone scalar file.
      const asArray = multiple || multiNames.has(name)
      const key = asArray ? `params[${name}][]` : `params[${name}]`
      fd.append(key, file, file.name)
    }
    return fd
  }

  // Append a param leaf to FormData under its bracketed key. FormData carries
  // only strings, so a NON-scalar param (a nested object or an array) is
  // bracket-EXPANDED into params[key][sub] / params[key][index][...] fields —
  // the SAME Rails-form shape the server's expand_bracket_keys / array_values
  // already parse, so a JSON body and a multipart body coerce identically
  // (issue #39). Previously a non-scalar was JSON.stringify'd into one
  // params[key]='<json>' field, which the server received as an un-decodable
  // String leaf and DROPPED (nested hash -> {}, array -> key removed).
  //
  // Arrays use NUMERIC indices (params[key][0], params[key][1]) — required for
  // an array-of-hash so each element's sub-keys stay grouped and the server's
  // index-hash sort rebuilds order; params[key][] would collapse them. A scalar
  // (string/number/boolean) is one string field, mirroring the JSON wire shape
  // (the server's :boolean/:integer casts read "true"/"42"). null/undefined is
  // an empty field. An EMPTY array/object emits NOTHING — FormData can't carry
  // []/{}, so the key is omitted and the action's keyword default applies (this
  // differs from the JSON path, where an explicit [] coerces to an empty array).
  #appendField(fd, key, value) {
    if (value == null) {
      fd.append(key, "")
    } else if (Array.isArray(value)) {
      value.forEach((element, index) => this.#appendField(fd, `${key}[${index}]`, element))
    } else if (typeof value === "object") {
      for (const [subKey, subValue] of Object.entries(value)) {
        this.#appendField(fd, `${key}[${subKey}]`, subValue)
      }
    } else {
      fd.append(key, String(value))
    }
  }

  // Names that appear more than once across the chosen files (a `multiple`
  // picker, or several file inputs sharing a name) — those go to params[name][]
  // so the server sees an array; a lone file stays params[name].
  #multiFileNames(files) {
    const counts = new Map()
    for (const { name } of files) counts.set(name, (counts.get(name) ?? 0) + 1)
    return new Set([...counts].filter(([, n]) => n > 1).map(([name]) => name))
  }

  #parseParams(raw) {
    if (!raw) return {}
    try {
      return typeof raw === "string" ? JSON.parse(raw) : raw
    } catch {
      return {}
    }
  }

  // Stimulus typecasts a JSON param to the parsed array already; a raw string
  // (hand-built attr, non-typecasting harness) is parsed here. Delegates to the
  // shared parseOps so the controller and the reactive:js stream action (issue
  // #97) treat a malformed ops attr identically (→ [], never a throw).
  #parseOps(raw) {
    return parseOps(raw)
  }

  // Interpret a [[name, args], ...] op list against this root (issue #95),
  // scoping each op's targets to this controller's own root via #opTargets (the
  // nested-reactive-root ownership filter, issue #15). The whitelist + skip
  // logic lives in the shared applyOps so runOps and the reactive:js stream
  // action interpret the SAME vocabulary the SAME way (client-side default-deny).
  #applyOps(list) {
    applyOps(list, (args) => this.#opTargets(args))
  }

  // Resolve an op's targets: "@root" is this element; a selector resolves
  // WITHIN this root and excludes nested reactive roots' subtrees (issue #15
  // semantics — the same nearest-root ownership check the field walk uses);
  // global: true opts a single op out to document-wide.
  #opTargets(args) {
    const to = args.to
    if (to === "@root") return [this.element]
    if (typeof to !== "string" || to === "") return []
    if (args.global) return [...document.querySelectorAll(to)]
    return [...this.element.querySelectorAll(to)].filter((el) => this.#ownsField(el))
  }

  // Whether a click-bound checkbox/radio trigger should keep its NATIVE flip
  // (issue #98). `checked: :keep` means "let the control flip now": the
  // unconditional preventDefault is exactly what suppresses that flip until the
  // morph, so we skip it — but ONLY for a checkbox/radio (a bare toggle click
  // has no form-navigation default to lose). Any other element (a button) keeps
  // preventDefault so an in-form submit can't navigate.
  #keepsNativeToggle(optimistic, target) {
    if (optimistic?.checked !== "keep") return false
    const type = target?.type
    return type === "checkbox" || type === "radio"
  }

  // Apply the OPTIMISTIC hint (issue #98) NOW and return its `undo` closure — the
  // exact ops to replay on FAILURE (optimistic reverts only when the round trip
  // fails; success leaves server truth or the deliberately-standing hint). It is
  // the same op vocabulary busy: uses (issue #181) via the one #applyHint engine;
  // the ONLY optimistic-specific op is checked: :keep (honorChecked = true).
  #applyOptimistic(optimistic, trigger) {
    if (!optimistic) return null
    const undo = this.#applyHint(optimistic, trigger, true)
    return undo.length ? undo : null
  }

  // Replay the recorded undo ops on failure (issue #98), guarded by isConnected:
  // a plain (non-morph) replace can detach this subtree before the failure lands,
  // and reverting a stale/detached node is pointless (it's gone) — so a
  // disconnected root skips the revert entirely. On success NOTHING calls this:
  // the server re-render overwrites the hint, or (reply.remove / streams-only)
  // the hint is deliberately left standing.
  #revertOptimistic(inverse) {
    if (!inverse) return
    if (!this.element.isConnected) return
    for (const undo of inverse) undo()
  }

  // Apply the BUSY state for THIS enqueue (issue #181) and return a `settle`
  // closure that undoes exactly this enqueue's contribution when the round trip
  // finishes (success OR any failure). Everything is refcounted so overlapping
  // enqueues never clobber: A's settle can't clear busy while B is still pending.
  //
  // Two layers:
  //   1. The ALWAYS-ON busy vocabulary (fires for every action, no hint needed):
  //      data-reactive-busy="<action>" on the trigger and the root (a
  //      space-separated, per-action refcounted set), aria-busy on the root (a
  //      pending counter), and data-reactive-busy on any busy_on element scoped
  //      to this action. Apps style a spinner with pure CSS and zero Ruby.
  //   2. The busy HINT (only when busy: was declared): the SAME cosmetic op set
  //      as optimistic: (class ops, hide/show, disable, text), applied through
  //      the one #applyHint engine and reverted on SETTLE (not on failure). These
  //      apply at ENQUEUE — never during a debounce quiet period — so a debounced
  //      input is not disabled mid-typing. checked: is optimistic-only, so busy:
  //      passes honorChecked = false (the Ruby on() already rejects it — this is
  //      belt-and-braces).
  #applyBusy(action, trigger, busy) {
    this.#markBusy(action, trigger)
    const undo = busy ? this.#applyHint(busy, trigger, false) : []

    let settled = false
    return () => {
      if (settled) return // one settle per enqueue, even if called twice
      settled = true
      this.#unmarkBusy(action, trigger)
      // Busy reverts on SETTLE regardless of outcome, guarded per element.
      for (const op of undo) op()
    }
  }

  // The ONE pending-state hint engine (issue #181), shared by optimistic: (revert
  // on failure) and busy: (revert on settle) — they differ only in WHEN the
  // returned undo ops run, never in the ops themselves. Applies the hint's
  // cosmetic ops to their targets (the trigger by default, or a `to:` selector
  // scoped to the root) and returns an array of undo closures. Class ops and
  // hide/show use a DELTA inverse (undo only what THIS call changed, so it
  // composes across overlapping enqueues); disable/text use a REFCOUNTED snapshot
  // (the true pre-hint value survives an overlapping enqueue that would otherwise
  // capture the already-swapped label as the "original"). `honorChecked` gates
  // checked: :keep — an optimistic-only native-control revert.
  #applyHint(hint, trigger, honorChecked) {
    const undo = []
    for (const el of this.#hintTargets(hint, trigger)) {
      if (hint.add_class) {
        // Undo only the classes this op ACTUALLY added — a class already present
        // was not our change, so reverting it would strip a class the element
        // legitimately had. Capture the real delta now.
        const added = hint.add_class.filter((c) => !el.classList.contains(c))
        el.classList.add(...added)
        if (added.length) undo.push(() => el.classList.remove(...added))
      }
      if (hint.remove_class) {
        // Symmetric: undo only the classes actually removed.
        const removed = hint.remove_class.filter((c) => el.classList.contains(c))
        el.classList.remove(...removed)
        if (removed.length) undo.push(() => el.classList.add(...removed))
      }
      if (hint.toggle_class) {
        // toggle_class is its own inverse regardless of prior state.
        hint.toggle_class.forEach((c) => el.classList.toggle(c))
        undo.push(() => hint.toggle_class.forEach((c) => el.classList.toggle(c)))
      }
      if (hint.hide) {
        el.hidden = true
        undo.push(() => (el.hidden = false))
      }
      if (hint.show) {
        el.hidden = false
        undo.push(() => (el.hidden = true))
      }
    }

    // disable/text swap the TRIGGER (a `to:` retargets only the class/hide/show
    // ops above — disable/text are inherently trigger affordances). Refcounted so
    // overlapping enqueues restore correctly.
    if (trigger && (hint.disable || hint.text != null)) {
      undo.push(this.#applyTextDisable(hint, trigger))
    }

    // checked: :keep — the native flip already happened on the trigger; record
    // the inverse (flip it back) so a revert restores the control's state.
    if (honorChecked && hint.checked === "keep" && trigger && "checked" in trigger) {
      const flipped = trigger.checked
      undo.push(() => (trigger.checked = !flipped))
    }

    return undo
  }

  // The elements a hint's class/hide/show ops apply to: the `to:` selector
  // (resolved like an op target — "@root" is the root, a selector is scoped to
  // this root's owned matches) or, with no `to:`, the trigger itself.
  #hintTargets(hint, trigger) {
    if (hint.to == null) return trigger ? [trigger] : []
    return this.#opTargets({ to: hint.to })
  }

  // Swap the trigger's disabled/innerHTML for a pending hint, snapshotting the
  // ORIGINAL once per trigger (refcounted so an overlapping enqueue never
  // snapshots the already-swapped "Saving…" as the original), and return the undo
  // closure. text swaps innerHTML (issue #181), NOT textContent: a composite
  // trigger like `<button><svg/> Save</button>` has child nodes, and
  // textContent = "Saving…" would DESTROY the icon; innerHTML preserves the
  // markup structure and restores it byte-for-byte.
  #applyTextDisable(hint, trigger) {
    const snap = this.#textDisableSnapshots.get(trigger)
    if (snap) {
      snap.count++
    } else {
      this.#textDisableSnapshots.set(trigger, {
        count: 1,
        disabled: trigger.disabled,
        html: trigger.innerHTML,
        hadText: hint.text != null,
        swappedTo: hint.text,
      })
    }

    if (hint.disable) trigger.disabled = true
    if (hint.text != null) trigger.innerHTML = hint.text

    return () => this.#restoreTextDisable(trigger, hint)
  }

  // Layer 1 — the always-on busy markers. Trigger + root carry the action token;
  // the root's counter drives aria-busy; busy_on elements scoped to this action
  // light up. Refcounts (#busyActions, #busyPending) so overlapping requests
  // don't clear each other.
  #markBusy(action, trigger) {
    this.#setBusyToken(trigger, action, +1)
    this.#setBusyToken(this.element, action, +1)

    this.#busyActions.set(action, (this.#busyActions.get(action) ?? 0) + 1)
    if (this.#busyPending++ === 0) this.element.setAttribute("aria-busy", "true")

    for (const el of this.#busyOnTargets(action)) this.#setBusyToken(el, action, +1)
  }

  #unmarkBusy(action, trigger) {
    this.#setBusyToken(trigger, action, -1)
    this.#setBusyToken(this.element, action, -1)

    const count = (this.#busyActions.get(action) ?? 1) - 1
    if (count <= 0) this.#busyActions.delete(action)
    else this.#busyActions.set(action, count)

    if (--this.#busyPending <= 0) {
      this.#busyPending = 0
      this.element.removeAttribute("aria-busy")
    }

    for (const el of this.#busyOnTargets(action)) this.#setBusyToken(el, action, -1)
  }

  // Add (+1) or remove (-1) `action` from an element's space-separated
  // data-reactive-busy token set, refcounted PER ELEMENT+ACTION so two queued
  // requests of the same action on the same element don't drop the token early
  // (and two DIFFERENT actions both keep their token — the set never clobbers).
  // The attribute is removed only when the set empties. No-op on a nullish/
  // detached element (a morph may have replaced the trigger before settle).
  #setBusyToken(el, action, delta) {
    if (!el || typeof el.getAttribute !== "function") return

    const counts = (this.#busyTokenCounts.get(el) ?? new Map())
    const next = (counts.get(action) ?? 0) + delta
    if (next <= 0) counts.delete(action)
    else counts.set(action, next)

    if (counts.size === 0) {
      this.#busyTokenCounts.delete(el)
      el.removeAttribute("data-reactive-busy")
      return
    }
    this.#busyTokenCounts.set(el, counts)
    el.setAttribute("data-reactive-busy", [...counts.keys()].join(" "))
  }

  // busy_on elements scoped to THIS action, owned by this root (not a nested
  // reactive root's, issue #15). data-reactive-busy-on="<action>" is the marker
  // busy_on(:action) emits.
  #busyOnTargets(action) {
    const nodes = this.element.querySelectorAll?.("[data-reactive-busy-on]") ?? []
    return [...nodes].filter(
      (el) => el.getAttribute("data-reactive-busy-on") === action && this.#ownsField(el),
    )
  }

  // Restore the trigger's disabled/innerHTML from its snapshot when the LAST
  // enqueue for that trigger settles (refcount → 0). GUARDED: skip a disconnected
  // trigger (a plain replace detached it — the node is gone), and do NOT restore
  // the label if it no longer equals what we swapped IN (a morph rendered a new
  // server label — clobbering it with the old markup would fight server truth).
  // The comparison + restore both use innerHTML so a composite trigger (icon +
  // label) round-trips its full markup, not a flattened text run (issue #181).
  #restoreTextDisable(trigger, hint) {
    const snap = this.#textDisableSnapshots.get(trigger)
    if (!snap) return
    if (--snap.count > 0) return // another enqueue for this trigger is still pending
    this.#textDisableSnapshots.delete(trigger)

    if (!trigger.isConnected) return // detached — nothing to restore

    if (hint.disable) trigger.disabled = snap.disabled
    if (snap.hadText && trigger.innerHTML === snap.swappedTo) trigger.innerHTML = snap.html
  }

  // Deploy-overlap read shim (issue #181): a page still rendered by the PREVIOUS
  // gem emits the old data-reactive-loading-param, whose `class:` key is the busy
  // vocabulary's `add_class:`. Remap it so an in-flight legacy page keeps its
  // pending affordance through the one #applyHint engine. Returns null for the
  // common (no legacy param) case so the fast path is untouched. Drop this shim
  // one minor after #181 ships (no page can still carry the old attr by then).
  #legacyLoadingHint(loading) {
    if (!loading || typeof loading !== "object") return null
    const { class: cls, ...rest } = loading
    return cls == null ? loading : { ...rest, add_class: cls }
  }

  // The action path comes from a <meta> tag that is fixed for the page's life,
  // so resolve it once per controller and cache it — avoids a querySelector on
  // every dispatch (this runs on the request hot path, once per click/keystroke
  // round trip). Cached on the instance, so a fresh connect() (after a Turbo
  // navigation swaps the element) re-reads it.
  #actionPath() {
    return (this.#actionPathCache ??=
      document.querySelector('meta[name="phlex-reactive-action-path"]')?.content ||
      "/reactive/actions")
  }

  // The per-request timeout in ms (issue #101), from a page-stable
  // <meta name="phlex-reactive-timeout"> (default 30000). Cached per-controller
  // like the action path. Parsed defensively: a missing/blank/non-positive/NaN
  // value falls back to the default, so a typo'd meta can never disable the
  // timeout (which would reintroduce the wedged-queue bug) or set a zero/negative
  // window that aborts instantly.
  #timeoutMs() {
    if (this.#timeoutMsCache != null) return this.#timeoutMsCache
    const raw = document.querySelector('meta[name="phlex-reactive-timeout"]')?.content
    const ms = Number(raw)
    return (this.#timeoutMsCache = Number.isFinite(ms) && ms > 0 ? ms : 30000)
  }

  // CSRF token and connection id are read LIVE (not cached) on purpose: Rails
  // can rotate the CSRF token, and the pgbus connection id changes on an SSE
  // reconnect — caching either would send a stale value. A single querySelector
  // per request is cheap next to the round trip itself.
  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }

  // The pgbus SSE connection id, if the page is subscribed to a stream. pgbus
  // reflects it onto the <pgbus-stream-source connection-id="…"> element (and
  // apps may mirror it to <meta name="pgbus-connection-id">). Returns null
  // when not present (e.g. no pgbus, or no active subscription) — the header
  // is then simply omitted.
  #connectionId() {
    return (
      document.querySelector("pgbus-stream-source[connection-id]")?.getAttribute("connection-id") ||
      document.querySelector('meta[name="pgbus-connection-id"]')?.content ||
      null
    )
  }
}
