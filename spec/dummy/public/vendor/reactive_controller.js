import { Controller } from "@hotwired/stimulus"

// The ONE generic controller behind every reactive Phlex component. It
// replaces the per-feature Stimulus controllers you'd otherwise hand-write
// for interactive components. A component declares its actions in Ruby (via
// Phlex::Reactive::Component); this controller binds DOM events to a single
// HTTP round trip and lets Turbo apply the re-rendered component back in
// (replace by default; method="morph" — Response.morph — preserves focus).
//
// Wire format (client -> server), POST <action path>, turbo-stream Accept:
//   { token: "<signed identity>", act: "<action>", params: {...} }
// (`act`, not `action`: `action` is a reserved Rails routing param.)
// The token is a MessageVerifier-signed { component, gid } — NO state is sent.
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
if (typeof window !== "undefined") {
  if (window.Turbo) registerReactiveVisit()
  else document.addEventListener("turbo:load", registerReactiveVisit, { once: true })
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

// Register this controller eagerly (not lazily) so a click immediately after
// page load is never missed. The phlex-reactive engine auto-pins it with
// preload: true for importmap apps; see the README for esbuild/webpack.
export default class extends Controller {
  static values = {
    token: String, // signed identity token (component + record gid/state)
  }

  #tokenCache // freshest token, threaded synchronously across queued requests
  #debounceTimers = new Map() // trigger element -> { timer, flush } pending dispatch

  // Mark that a reactive controller actually connected, so the registration
  // guard above knows the controller was registered (issue #26 part 2).
  connect() {
    reactiveConnected = true
  }

  // Tear down any pending debounce timers when the controller leaves the DOM
  // (Turbo morph/navigation removes the element). Otherwise a timer that hasn't
  // fired yet would later call #enqueue on a disconnected controller — a round
  // trip against a detached element / stale token (issue #17 follow-up).
  disconnect() {
    this.#clearAllDebounces()
  }

  // Serialize requests per component. Each round trip rewrites the signed
  // token in the DOM (state lives in the token, not the client). If events
  // fire faster than round trips complete, concurrent requests would all read
  // the SAME stale token and clobber each other (last-write-wins). Chaining on
  // a per-controller promise makes each dispatch wait for the previous one, so
  // it always uses the freshest token.
  dispatch(event) {
    const { action, params, debounce } = event.params
    if (!action) return

    // Stop native behavior (button submit / FORM NAVIGATION) HERE, synchronously
    // within the event dispatch. preventDefault() only works while the event is
    // still being handled — deferring it into the request-queue microtask (below)
    // is too late: a `submit` trigger would natively POST the form and navigate
    // before the reactive round trip runs (issue #11). For a `click` trigger
    // there's no default to miss, so this was previously invisible. This holds
    // for debounced triggers too — the round trip is deferred, but the native
    // default must still be prevented now.
    event.preventDefault()

    // Debounced trigger (e.g. on(:update, event: "input", debounce: 300)):
    // coalesce rapid events into ONE round trip after a quiet period, instead of
    // one POST per keystroke (issue #17). A blur flushes a pending dispatch.
    const ms = Number(debounce) || 0
    if (ms > 0) return this.#debounceDispatch(event.target, ms, action, params)

    // Capture action/params now; the queued work runs in a later microtask, by
    // which point the event object may have been reset by the browser.
    return this.#enqueue(action, params)
  }

  #enqueue(action, params) {
    this.queue = (this.queue ?? Promise.resolve()).then(() => this.#perform(action, params))
    return this.queue
  }

  // Reset a per-element timer; only enqueue the round trip after `ms` of quiet.
  // Also flush immediately on blur so leaving the field never drops the last
  // edit (a long debounce shouldn't swallow a value the user tabbed away from).
  #debounceDispatch(target, ms, action, params) {
    this.#clearDebounce(target)

    const flush = () => {
      this.#clearDebounce(target)
      this.#enqueue(action, params)
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

  async #perform(action, params) {
    // Auto-collect named field values inside this component so a button-
    // triggered action still receives sibling inputs (Livewire-style).
    // Explicit params (data-reactive-params-param) win over collected fields.
    const fieldParams = this.#collectFields()

    const body = JSON.stringify({
      token: this.#currentToken,
      act: action,
      params: { ...fieldParams, ...this.#parseParams(params) },
    })

    this.element.setAttribute("aria-busy", "true")

    try {
      const headers = {
        "Content-Type": "application/json",
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.#csrfToken(),
      }
      // Send the pgbus SSE connection id (if subscribed) so the server can
      // exclude this connection from its own broadcast echo — the actor
      // already gets the action's HTTP response. Harmless without pgbus.
      const connectionId = this.#connectionId()
      if (connectionId) headers["X-Pgbus-Connection"] = connectionId

      const response = await fetch(this.#actionPath(), {
        method: "POST",
        headers,
        body,
        credentials: "same-origin",
      })

      if (response.redirected) {
        console.error("[phlex-reactive] action was redirected (auth/CSRF?) — no update applied")
        return
      }
      if (!response.ok) {
        console.error(`[phlex-reactive] action failed: HTTP ${response.status}`, await response.text())
        return
      }

      const contentType = response.headers.get("Content-Type") || ""
      if (!contentType.includes("turbo-stream")) {
        console.error(`[phlex-reactive] expected a turbo-stream, got "${contentType}" — no update applied`)
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
    } catch (error) {
      console.error("[phlex-reactive] action error", error)
    } finally {
      this.element.removeAttribute("aria-busy")
    }
  }

  get #currentToken() {
    return this.#tokenCache ?? this.tokenValue
  }

  set #currentToken(value) {
    this.#tokenCache = value
  }

  #extractToken(html) {
    const match = html.match(/data-reactive-token-value="([^"]+)"/)
    return match?.[1]
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

  #collectFields() {
    const fields = {}
    // Standard form controls owned by THIS root (not a nested reactive root).
    this.element.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (!this.#ownsField(field)) return
      if (field.type === "checkbox") {
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
    return fields
  }

  #parseParams(raw) {
    if (!raw) return {}
    try {
      return typeof raw === "string" ? JSON.parse(raw) : raw
    } catch {
      return {}
    }
  }

  #actionPath() {
    return (
      document.querySelector('meta[name="phlex-reactive-action-path"]')?.content ||
      "/reactive/actions"
    )
  }

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
