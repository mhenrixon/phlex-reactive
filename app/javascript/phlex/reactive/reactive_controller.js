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

export function registerReactiveActions() {
  registerReactiveVisit()
  registerReactiveToken()
  registerReactiveJs()
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
// ownership filter: a server-pushed op names its own scope explicitly.
function streamOpTargets(args, root) {
  const to = args.to
  if (root) {
    if (to === "@root") return [root]
    if (typeof to !== "string" || to === "") return []
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
  // Loading-state bookkeeping (issue #99). All keyed so overlapping enqueues
  // refcount correctly and never clobber each other:
  #busyPending = 0 // root aria-busy pending counter (remove only at zero)
  #busyActions = new Map() // action -> in-flight count (root's space-separated busy set + busy_on)
  #busyTokenCounts = new WeakMap() // element -> Map(action -> count): its data-reactive-busy token set
  #loadingSnapshots = new Map() // trigger element -> { count, disabled, text } refcounted snapshot

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
    const { action, params, debounce, throttle, confirm, outside, window: windowBound, optimistic, loading } =
      event.params
    if (!action) return

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
    if (!confirm) return this.#proceed(target, action, params, debounce, throttle, optimistic, loading)

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
        if (ok) this.#proceed(target, action, params, debounce, throttle, optimistic, loading)
      })
  }

  // CLIENT-ONLY trigger entry point (issue #95) — the zero-round-trip sibling
  // of dispatch(). Wired by on_client: applies the declared op chain
  // (data-reactive-ops-param, built by Phlex::Reactive::JS) locally. NO token,
  // NO params, NO fetch, ever. Ops are ephemeral UI: any server re-render of
  // the component resets whatever they toggled (by design — a signed action
  // owns state that must survive re-renders).
  runOps(event) {
    const { ops, outside, window: windowBound } = event.params

    // Outside guard FIRST — identical semantics to dispatch() (issue #80): an
    // outside: trigger is a COMPLETE no-op for events inside this root, before
    // preventDefault and before any op runs.
    if (outside && this.element.contains(event.target)) return

    // Element-bound triggers preventDefault (a bare button inside a <form>
    // must not submit it); window-bound triggers (window:/outside:) never do —
    // they hear every matching event on the page, and preventDefault-ing those
    // would kill native clicks site-wide (issue #80 rationale).
    if (!windowBound) event.preventDefault()

    this.#applyOps(this.#parseOps(ops))
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
    const key = this.element.getAttribute("data-reactive-compute-reducer-param")
    if (!key) return
    const reduce = computeReducer(key)
    if (!reduce) return

    const inputs = this.#parseComputeList("data-reactive-compute-inputs-param")
    const outputs = this.#parseComputeList("data-reactive-compute-outputs-param")

    const values = {}
    for (const name of inputs) values[name] = this.#numericFieldValue(name)

    const result = reduce(values, { changed: this.#changedComputeField(event, inputs) }) || {}
    for (const name of outputs) {
      if (!(name in result)) continue
      const field = this.#ownedField(name)
      if (!field) continue
      // Real browsers do NOT fire `input` on a programmatic .value write (issue
      // #76), so after writing we dispatch a bubbling `input` ourselves — that's
      // what drives a chained repaint (a summary listener, a second compute),
      // matching the server's set_value + dispatch("input") contract. The write
      // is CHANGE-GUARDED: an unchanged value is skipped entirely (no write, no
      // event). The guard is what lets a reducer with overlapping inputs/outputs
      // (the shipped payment_split shape) settle — an unconditional dispatch
      // would re-enter input->reactive#recompute forever.
      if (String(result[name]) === field.value) continue
      field.value = result[name]
      field.dispatchEvent(new Event("input", { bubbles: true }))
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
  // unset. Falls back to the root for a directly-invoked call (unit tests).
  #listnavOptions(event) {
    const trigger = event?.currentTarget ?? event?.target ?? this.element
    const selector =
      trigger.getAttribute?.("data-reactive-listnav-option-param") ??
      this.element.getAttribute("data-reactive-listnav-option-param")
    if (!selector) return []
    const nodes = this.element.querySelectorAll(selector)
    return Array.from(nodes).filter((el) => this.#ownsField(el))
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

  // The declared compute input the event just edited — the reducer's
  // meta.changed (issue #75). The triggering field counts only when it is a
  // named form control OWNED by this root (not a nested reactive root's, issue
  // #15) AND its name is among the declared compute inputs; anything else
  // (a direct call, an unowned/undeclared target) yields null.
  #changedComputeField(event, inputs) {
    const target = event?.target
    if (!target?.name || typeof target.closest !== "function") return null
    if (!inputs.includes(target.name)) return null
    return this.#ownsField(target) ? target.name : null
  }

  // The first named control owned by THIS root (skips nested reactive roots,
  // issue #15) — used by recompute to read inputs and write outputs.
  #ownedField(name) {
    const nodes = this.element.querySelectorAll(`[name="${name}"]`)
    for (const el of nodes) if (this.#ownsField(el)) return el
    return null
  }

  // A field's value as a Number, treating blank/absent/NaN as 0 — mirroring the
  // nanToZero coercion the hand-written calculators use, so a reducer never sees
  // "" or NaN for an empty field.
  #numericFieldValue(name) {
    const field = this.#ownedField(name)
    const n = Number(field?.value)
    return Number.isFinite(n) ? n : 0
  }

  // Enqueue the action — debounced if a debounce window is set, else immediately.
  // Split out of dispatch so both the no-confirm fast path and the post-confirm
  // microtask share one place (issue #55). `target` is captured up front because
  // this can run in a later microtask, after event.target has been reset.
  #proceed(target, action, params, debounce, throttle, optimistic, loading) {
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
    // The optimistic hint (issue #98) and the loading state (issue #99) ride to
    // the flush too, so they apply ONCE per enqueue — a debounced input must not
    // flap toggle_class per keystroke, and its element must NOT be disabled
    // during the quiet period (that would break typing). Both apply at ENQUEUE.
    const ms = Number(debounce) || 0
    if (ms > 0) return this.#debounceDispatch(target, ms, action, params, optimistic, loading)

    // Throttled trigger (e.g. on(:track, event: "scroll", window: true,
    // throttle: 250), issue #80): LEADING-EDGE rate limit — fire the first
    // event immediately, drop the rest until the window elapses. debounce and
    // throttle are mutually exclusive (the Ruby on() raises on both).
    const throttleMs = Number(throttle) || 0
    if (throttleMs > 0) return this.#throttleDispatch(target, throttleMs, action, params, optimistic, loading)

    return this.#enqueue(action, params, optimistic, target, loading)
  }

  // Apply the optimistic hint ONCE (recording its inverse) and chain the round
  // trip, threading that inverse onto THIS queued request so the serialized
  // per-controller queue reverts the RIGHT request's hint on failure (issue
  // #98). Applying here — the single flush/enqueue point every path funnels
  // through — is what makes a hint apply once per enqueue, not per raw dispatch.
  //
  // The loading state (issue #99) applies here too, for the same reason: enqueue
  // is the moment the request is committed to the queue, so the always-on busy
  // vocabulary (data-reactive-busy on the trigger + root, aria-busy via a pending
  // counter, busy_on scoping) and the loading hint (disable + class + text swap)
  // cover the WHOLE pending window — queue wait included — not just the fetch. It
  // returns a `settle` closure that #perform runs in its finally (success OR
  // failure), guarded so a morph-replaced trigger is never clobbered.
  #enqueue(action, params, optimistic, target, loading) {
    const inverse = this.#applyOptimistic(optimistic, target)
    const settle = this.#applyLoading(action, target, loading)
    this.queue = (this.queue ?? Promise.resolve()).then(() => this.#perform(action, params, inverse, settle))
    return this.queue
  }

  // Reset a per-element timer; only enqueue the round trip after `ms` of quiet.
  // Also flush immediately on blur so leaving the field never drops the last
  // edit (a long debounce shouldn't swallow a value the user tabbed away from).
  #debounceDispatch(target, ms, action, params, optimistic, loading) {
    this.#clearDebounce(target)

    const flush = () => {
      this.#clearDebounce(target)
      this.#enqueue(action, params, optimistic, target, loading)
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
  #throttleDispatch(target, ms, action, params, optimistic, loading) {
    const timers = this.#throttleTimers.get(target) ?? new Map()
    if (timers.has(action)) return // inside the window — suppress

    const timer = setTimeout(() => {
      timers.delete(action)
      if (timers.size === 0) this.#throttleTimers.delete(target)
    }, ms)
    timers.set(action, timer)
    this.#throttleTimers.set(target, timers)
    return this.#enqueue(action, params, optimistic, target, loading) // leading edge: fire NOW
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

  async #perform(action, params, inverse, settle) {
    // Auto-collect named field values inside this component so a button-
    // triggered action still receives sibling inputs (Livewire-style), plus any
    // chosen file inputs in the SAME walk. Explicit params
    // (data-reactive-params-param) win over collected fields.
    const { fields, files } = this.#collectFields()
    const allParams = { ...fields, ...this.#parseParams(params) }
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

    // aria-busy on the root is now driven by the loading pending counter
    // (#applyLoading, applied at ENQUEUE so it covers the queue wait too), not
    // set here. #settleLoading in the finally clears it — see #enqueue.

    try {
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
        })
      } catch (error) {
        console.error("[phlex-reactive] action error", error)
        this.#revertOptimistic(inverse)
        this.#emitError(action, params, allParams, { kind: "network" })
        return
      }

      if (response.redirected) {
        console.error("[phlex-reactive] action was redirected (auth/CSRF?) — no update applied")
        this.#revertOptimistic(inverse)
        this.#emitError(action, params, allParams, { kind: "redirected", status: response.status })
        return
      }
      if (!response.ok) {
        const errorBody = await response.text()
        console.error(`[phlex-reactive] action failed: HTTP ${response.status}`, errorBody)
        this.#revertOptimistic(inverse)
        this.#emitError(action, params, allParams, { kind: "http", status: response.status, body: errorBody })
        return
      }

      const contentType = response.headers.get("Content-Type") || ""
      if (!contentType.includes("turbo-stream")) {
        console.error(`[phlex-reactive] expected a turbo-stream, got "${contentType}" — no update applied`)
        this.#revertOptimistic(inverse)
        this.#emitError(action, params, allParams, { kind: "content-type", status: response.status })
        return
      }

      const html = await response.text()
      // Capture the new token from the response synchronously, so the next
      // queued request uses it without waiting for the async DOM morph.
      this.#currentToken = this.#extractToken(html) ?? this.#currentToken
      // Turbo applies the <turbo-stream> ops by id. A plain replace is an
      // outerHTML swap (focus on the replaced subtree is lost); a method="morph"
      // replace (Response.morph) or an update morphs in place, preserving the
      // focused input + caret on unchanged nodes — see issue #28.
      window.Turbo.renderStreamMessage(html)
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
    }
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

    // The dedicated token-only refresh for THIS element (partial updates / the
    // collection container) — an attribute on the <turbo-stream> itself.
    const tokenStream = html.match(
      new RegExp(
        `<turbo-stream\\b[^>]*\\baction="reactive:token"[^>]*\\btarget="${escapeRegExp(id)}"[^>]*\\bdata-reactive-token-value="([^"]+)"`,
      ),
    )
    if (tokenStream) return tokenStream[1]

    // A full self re-render: a replace/update of THIS element whose template root
    // carries the fresh token. Scope the token search to that one stream so a
    // sibling/child token elsewhere in the body can't leak in.
    const selfStream = html.match(
      new RegExp(
        `<turbo-stream\\b[^>]*\\baction="(?:replace|update)"[^>]*\\btarget="${escapeRegExp(id)}"[^>]*>([\\s\\S]*?)</turbo-stream>`,
      ),
    )
    if (selfStream) return selfStream[1].match(/data-reactive-token-value="([^"]+)"/)?.[1]

    // Nothing re-rendered our id — keep the current token.
    return undefined
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

  // One walk over THIS root's named controls (not a nested reactive root's),
  // returning both the scalar `fields` and any chosen `files`. A file input's
  // `.value` is the useless "C:\fakepath\…" string, never a scalar — so its
  // chosen files are collected separately (honoring `multiple`) and it adds no
  // phantom blank value (issue #34). An empty `files` keeps the JSON path.
  #collectFields() {
    const fields = {}
    const files = []
    this.element.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (!this.#ownsField(field)) return
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
        if (!this.#ownsField(el)) return // skip editors owned by a nested reactive root (issue #15)
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

  // Apply the optimistic hint (issue #98) to its targets NOW and return the
  // INVERSE — the exact ops to replay on failure. Cosmetic only: class ops and
  // hidden, applied to the trigger by default or to a `to:` selector scoped to
  // the root. `checked: :keep` records the trigger's post-flip state so a
  // failure snaps the native control back; it applies no DOM change itself (the
  // browser already flipped it). Returns null when there is nothing to do, so
  // the success/failure paths can cheaply skip.
  #applyOptimistic(optimistic, trigger) {
    if (!optimistic) return null

    // Class + hidden ops share one target set (trigger, or the `to:` selector).
    const targets = this.#optimisticTargets(optimistic, trigger)
    const undo = []
    for (const el of targets) {
      if (optimistic.add_class) {
        // Undo only the classes this op ACTUALLY added — a class already present
        // was not our change, so reverting it would strip a class the element
        // legitimately had (the add was a no-op). Capture the real delta now.
        const added = optimistic.add_class.filter((c) => !el.classList.contains(c))
        el.classList.add(...added)
        if (added.length) undo.push(() => el.classList.remove(...added))
      }
      if (optimistic.remove_class) {
        // Symmetric: undo only the classes actually removed — one already absent
        // wasn't our change, so re-adding it would introduce a class that wasn't
        // there before.
        const removed = optimistic.remove_class.filter((c) => el.classList.contains(c))
        el.classList.remove(...removed)
        if (removed.length) undo.push(() => el.classList.add(...removed))
      }
      if (optimistic.toggle_class) {
        // toggle_class is its own inverse regardless of prior state — toggling
        // the same classes back exactly restores it, no delta tracking needed.
        optimistic.toggle_class.forEach((c) => el.classList.toggle(c))
        undo.push(() => optimistic.toggle_class.forEach((c) => el.classList.toggle(c)))
      }
      if (optimistic.hide) {
        el.hidden = true
        undo.push(() => (el.hidden = false))
      }
    }

    // checked: :keep — the native flip already happened on the trigger; record
    // the inverse (flip it back) so a failure reverts the control's state.
    if (optimistic.checked === "keep" && trigger && "checked" in trigger) {
      const flipped = trigger.checked
      undo.push(() => (trigger.checked = !flipped))
    }

    return undo.length ? undo : null
  }

  // Replay the recorded inverse ops on failure (issue #98), guarded by
  // isConnected: a plain (non-morph) replace can detach this subtree before the
  // failure lands, and reverting a stale/detached node is pointless (it's gone)
  // — so a disconnected root skips the revert entirely. On success NOTHING calls
  // this: the server re-render overwrites the hint, or (reply.remove /
  // streams-only) the hint is deliberately left standing.
  #revertOptimistic(inverse) {
    if (!inverse) return
    if (!this.element.isConnected) return
    for (const undo of inverse) undo()
  }

  // The elements an optimistic class/hidden hint applies to: the `to:` selector
  // (resolved like an op target — "@root" is the root, a selector is scoped to
  // this root's owned matches) or, with no `to:`, the trigger itself.
  #optimisticTargets(optimistic, trigger) {
    if (optimistic.to == null) return trigger ? [trigger] : []
    return this.#opTargets({ to: optimistic.to })
  }

  // Apply the loading state for THIS enqueue (issue #99) and return a `settle`
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
  //   2. The loading HINT (only when loading:/disable_with: was declared):
  //      disable the trigger, add a loading class (to the trigger or a `to:`
  //      target), swap its text. These apply at ENQUEUE — never during a debounce
  //      quiet period — so a debounced input is not disabled mid-typing.
  #applyLoading(action, trigger, loading) {
    this.#markBusy(action, trigger)
    const restoreHint = this.#applyLoadingHint(action, trigger, loading)

    let settled = false
    return () => {
      if (settled) return // one settle per enqueue, even if called twice
      settled = true
      this.#unmarkBusy(action, trigger)
      restoreHint()
    }
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

  // Layer 2 — the loading HINT (disable + class + text). Snapshots the trigger's
  // ORIGINAL disabled/text/classes on the FIRST enqueue for that trigger
  // (refcounted so an overlapping enqueue never snapshots the already-swapped
  // "Saving…" as the original), applies the swap, and returns a restore closure.
  // With no hint, returns a no-op restore (the always-on busy markers still ran).
  #applyLoadingHint(action, trigger, loading) {
    if (!loading || !trigger) return () => {}

    const classTargets = this.#loadingTargets(loading, trigger)
    const classes = Array.isArray(loading.class) ? loading.class : []
    const addedByTarget = []
    for (const el of classTargets) {
      const added = classes.filter((c) => !el.classList.contains(c))
      el.classList.add(...added)
      if (added.length) addedByTarget.push([el, added])
    }

    // Snapshot disabled/text ONCE per trigger (refcounted). A second overlapping
    // enqueue increments the count but does NOT re-snapshot — so the recorded
    // "original" is the true pre-loading state, never the swapped label.
    const snap = this.#loadingSnapshots.get(trigger)
    if (snap) {
      snap.count++
    } else if (loading.disable || loading.text != null) {
      this.#loadingSnapshots.set(trigger, {
        count: 1,
        disabled: trigger.disabled,
        text: trigger.textContent,
        hadText: loading.text != null,
      })
    }

    if (loading.disable) trigger.disabled = true
    if (loading.text != null) trigger.textContent = loading.text

    return () => {
      for (const [el, added] of addedByTarget) if (el.isConnected) el.classList.remove(...added)
      this.#restoreLoadingSnapshot(trigger, loading)
    }
  }

  // Restore the trigger's disabled/text from its snapshot when the LAST enqueue
  // for that trigger settles (refcount → 0). GUARDED: skip a disconnected
  // trigger (a plain replace detached it — the node is gone), and do NOT restore
  // the text if it no longer equals what we swapped IN (a morph rendered a new
  // server label — clobbering it with the old text would fight server truth).
  #restoreLoadingSnapshot(trigger, loading) {
    const snap = this.#loadingSnapshots.get(trigger)
    if (!snap) return
    if (--snap.count > 0) return // another enqueue for this trigger is still pending
    this.#loadingSnapshots.delete(trigger)

    if (!trigger.isConnected) return // detached — nothing to restore

    if (loading.disable) trigger.disabled = snap.disabled
    // Only restore the label if the trigger still shows OUR swapped text; a
    // changed textContent means the server morph relabeled it — leave it.
    if (snap.hadText && trigger.textContent === loading.text) trigger.textContent = snap.text
  }

  // The elements a loading class applies to: the `to:` selector (resolved like
  // an op target — "@root" is the root, a selector is scoped to this root's
  // owned matches) or, with no `to:`, the trigger itself.
  #loadingTargets(loading, trigger) {
    if (loading.to == null) return trigger ? [trigger] : []
    return this.#opTargets({ to: loading.to })
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
