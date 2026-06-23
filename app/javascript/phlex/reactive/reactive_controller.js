import { Controller } from "@hotwired/stimulus"

// The ONE generic controller behind every reactive Phlex component. It
// replaces the per-feature Stimulus controllers you'd otherwise hand-write
// for interactive components. A component declares its actions in Ruby (via
// Phlex::Reactive::Component); this controller binds DOM events to a single
// HTTP round trip and lets Turbo morph the re-rendered component back in.
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
// Register this controller eagerly (not lazily) so a click immediately after
// page load is never missed. The phlex-reactive engine auto-pins it with
// preload: true for importmap apps; see the README for esbuild/webpack.
export default class extends Controller {
  static values = {
    token: String, // signed identity token (component + record gid/state)
  }

  #tokenCache // freshest token, threaded synchronously across queued requests

  // Serialize requests per component. Each round trip rewrites the signed
  // token in the DOM (state lives in the token, not the client). If events
  // fire faster than round trips complete, concurrent requests would all read
  // the SAME stale token and clobber each other (last-write-wins). Chaining on
  // a per-controller promise makes each dispatch wait for the previous one, so
  // it always uses the freshest token.
  dispatch(event) {
    this.queue = (this.queue ?? Promise.resolve()).then(() => this.#perform(event))
    return this.queue
  }

  async #perform(event) {
    const { action, params } = event.params
    if (!action) return

    // Stop native behavior (button submit / form navigation): the reactive
    // round trip replaces it.
    event.preventDefault()

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
      // Turbo applies the <turbo-stream> ops (replace/morph by id), preserving
      // focus/scroll/listeners on unchanged nodes.
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

  #collectFields() {
    const fields = {}
    this.element.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (field.type === "checkbox") {
        fields[field.name] = field.checked
      } else if (field.type === "radio") {
        if (field.checked) fields[field.name] = field.value
      } else {
        fields[field.name] = field.value
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
