// Unit tests for the user-visible failure surface (issue #100):
//
//   1. Non-OK turbo-stream bodies are RENDERED (not just console.error'd): when
//      !response.ok BUT the Content-Type is turbo-stream, the body is read, run
//      through #extractToken (which no-ops when nothing re-renders our id — a 400
//      InvalidToken body never refreshes the held token), handed to
//      Turbo.renderStreamMessage, and data-reactive-error="<kind>" is set on the
//      root. The existing reactive:error (kind http) STILL fires. The next
//      successful apply clears data-reactive-error.
//   2. A network failure (no server to render anything) clones the content of a
//      server-rendered <template data-reactive-error-flash> into the flash region.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll } from "bun:test"

let ReactiveController

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
})

// A reactive root stub that RECORDS attribute writes so a test can assert
// data-reactive-error was set/cleared. Records dispatched events too.
function makeRoot({ connected = true, id = "counter" } = {}) {
  const attrs = {}
  const events = []
  return {
    attrs,
    events,
    isConnected: connected,
    id,
    dispatchEvent: (event) => events.push(event),
    querySelectorAll: () => [],
    setAttribute: (name, value) => (attrs[name] = String(value)),
    removeAttribute: (name) => delete attrs[name],
    getAttribute: (name) => attrs[name] ?? null,
    hasAttribute: (name) => name in attrs,
  }
}

function buildController(responses, { root, template } = {}) {
  const controller = new ReactiveController()
  controller.element = root ?? makeRoot()
  controller.tokenValue = "tok"
  let calls = 0
  globalThis.fetch = () => {
    const script = responses[Math.min(calls, responses.length - 1)]
    calls++
    if (script.reject) return Promise.reject(script.reject)
    return Promise.resolve({
      redirected: script.redirected ?? false,
      ok: script.ok ?? true,
      status: script.status ?? 200,
      headers: { get: () => script.contentType ?? "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(script.body ?? ""),
    })
  }

  // A flash container the network fallback clones the template into.
  const flash = { children: [], appendChild: (node) => flash.children.push(node) }
  globalThis.document = {
    querySelector: (sel) => {
      if (sel === 'meta[name="phlex-reactive-action-path"]') return { content: "/reactive/actions" }
      if (sel === 'meta[name="csrf-token"]') return { content: "csrf" }
      if (sel === "[data-reactive-error-flash]") return template ?? null
      return null
    },
    getElementById: (elId) => (elId === "flash" ? flash : null),
    dispatchEvent: () => {},
  }
  const rendered = []
  globalThis.window = {
    Turbo: { renderStreamMessage: (html) => rendered.push(html) },
  }
  return { controller, calls: () => calls, rendered, flash }
}

function click(controller, extra = {}) {
  return controller.dispatch({
    params: { action: "save", params: '{"n":1}', ...extra },
    preventDefault: () => {},
  })
}

function eventsNamed(root, name) {
  return root.events.filter((event) => event.type === name)
}

// --- 1. Non-OK turbo-stream bodies are rendered -----------------------------

test("a non-OK turbo-stream body is rendered via Turbo.renderStreamMessage", async () => {
  const body =
    '<turbo-stream action="append" target="flash"><template>' +
    '<div class="reactive-flash reactive-flash--error">nope</div></template></turbo-stream>'
  const root = makeRoot()
  const { controller, rendered } = buildController([{ ok: false, status: 422, body }], { root })

  await click(controller)

  // The error body was HANDED TO Turbo (not discarded).
  expect(rendered).toContain(body)
})

test("a non-OK turbo-stream response STILL fires reactive:error kind=http with status+body", async () => {
  const body = '<turbo-stream action="append" target="flash"><template>x</template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ ok: false, status: 422, body }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("http")
  expect(event.detail.status).toBe(422)
  expect(event.detail.body).toBe(body)
})

test("data-reactive-error is set to the kind on a non-OK turbo-stream failure", async () => {
  const body = '<turbo-stream action="append" target="flash"><template>x</template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ ok: false, status: 422, body }], { root })

  await click(controller)

  expect(root.attrs["data-reactive-error"]).toBe("http")
})

test("a non-turbo-stream non-OK body is NOT rendered (only console.error'd, as before)", async () => {
  const root = makeRoot()
  const { controller, rendered } = buildController(
    [{ ok: false, status: 500, contentType: "text/html", body: "<html>error</html>" }],
    { root },
  )

  await click(controller)

  expect(rendered.length).toBe(0)
  // But the attribute + event still fire — the failure is still surfaced.
  expect(root.attrs["data-reactive-error"]).toBe("http")
  expect(eventsNamed(root, "reactive:error")[0].detail.kind).toBe("http")
})

test("a 400 error body does NOT refresh the held token (extractToken no-ops on a foreign body)", async () => {
  // A 400 body that re-renders 'flash', not our 'counter' id: #extractToken must
  // return undefined, so the retry-valid held token is unchanged (issue #100 note).
  const body =
    '<turbo-stream action="append" target="flash">' +
    '<template><div data-reactive-token-value="ATTACKER-TOKEN">x</div></template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ ok: false, status: 400, body }], { root })

  await click(controller)

  // The next request must still carry the ORIGINAL token, not a token lifted
  // from a body that never re-rendered our id.
  expect(controller.tokenValue).toBe("tok")
})

test("the next successful apply CLEARS data-reactive-error", async () => {
  const errBody = '<turbo-stream action="append" target="flash"><template>x</template></turbo-stream>'
  const okBody = '<turbo-stream action="replace" target="counter"><template>' +
    '<div id="counter" data-reactive-token-value="fresh"></div></template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ ok: false, status: 422, body: errBody }, { body: okBody }], { root })

  await click(controller)
  expect(root.attrs["data-reactive-error"]).toBe("http")

  await click(controller)
  expect(root.attrs["data-reactive-error"]).toBeUndefined()
})

// --- 2. Network fallback clones the error-flash template ---------------------

test("a network failure clones <template data-reactive-error-flash> into the flash region", async () => {
  const cloned = { tag: "cloned-node" }
  const template = {
    content: { cloneNode: (deep) => (deep ? cloned : null) },
    getAttribute: () => null, // no explicit target → defaults to "flash"
  }
  const root = makeRoot()
  const { controller, flash } = buildController([{ reject: new Error("offline") }], { root, template })

  await click(controller)

  // The template's content was deep-cloned into the flash container.
  expect(flash.children).toContain(cloned)
  // The network error still surfaces as usual.
  expect(eventsNamed(root, "reactive:error")[0].detail.kind).toBe("network")
})

test("a network failure with NO template present degrades silently (no throw)", async () => {
  const root = makeRoot()
  const { controller, flash } = buildController([{ reject: new Error("offline") }], { root, template: null })

  await click(controller)

  expect(flash.children.length).toBe(0)
  expect(eventsNamed(root, "reactive:error")[0].detail.kind).toBe("network")
})
