// Unit tests for the client lifecycle CustomEvents (issue #79):
//
//   reactive:before-dispatch  — cancelable veto point, fired in #proceed
//                               (post-preventDefault, post-confirm, PRE-debounce);
//                               preventDefault() skips debounce/enqueue entirely.
//   reactive:applied          — after token extraction + Turbo.renderStreamMessage;
//                               detail { action, params, html }.
//   reactive:error            — in all four #perform failure branches, kind:
//                               redirected | http | content-type | network, with a
//                               retry() that re-enters the request queue (and
//                               no-ops with a console.warn when the root left
//                               the DOM).
//
// Events go out via RAW dispatchEvent — Stimulus's this.dispatch() helper is
// SHADOWED by the controller's own dispatch(event) action method — on the root
// element when connected, else on document (a bubbling event on a detached node
// never reaches document listeners).
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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// A reactive root stub that records every CustomEvent raw-dispatched on it.
function makeRoot({ connected = true } = {}) {
  const events = []
  return {
    events,
    isConnected: connected,
    id: "counter",
    dispatchEvent: (event) => events.push(event),
    querySelectorAll: () => [],
    setAttribute: () => {},
    removeAttribute: () => {},
    getAttribute: () => null,
  }
}

// Build a controller with a scripted fetch. `responses` is a list of fetch
// outcomes ({...response fields} or { reject: Error }) consumed in order; the
// last one repeats.
function buildController(responses, { root } = {}) {
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
  const documentEvents = []
  globalThis.document = {
    querySelector: () => null,
    dispatchEvent: (event) => documentEvents.push(event),
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, calls: () => calls, documentEvents }
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

// --- reactive:before-dispatch ---------------------------------------------

test("before-dispatch fires with {action, params, element} and is cancelable", async () => {
  const root = makeRoot()
  const { controller, calls } = buildController([{}], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:before-dispatch")
  expect(event).toBeDefined()
  expect(event.cancelable).toBe(true)
  expect(event.bubbles).toBe(true)
  expect(event.composed).toBe(true)
  expect(event.detail.action).toBe("save")
  expect(event.detail.params).toEqual({ n: 1 })
  expect(event.detail.element).toBe(root)
  expect(calls()).toBe(1)
})

test("before-dispatch preventDefault() cancels the round trip (no fetch)", async () => {
  const root = makeRoot()
  root.dispatchEvent = (event) => {
    root.events.push(event)
    if (event.type === "reactive:before-dispatch") event.preventDefault()
  }
  const { controller, calls } = buildController([{}], { root })

  await click(controller)

  expect(calls()).toBe(0)
})

test("before-dispatch preventDefault() also skips a DEBOUNCED dispatch (nothing scheduled)", async () => {
  const root = makeRoot()
  root.dispatchEvent = (event) => {
    root.events.push(event)
    if (event.type === "reactive:before-dispatch") event.preventDefault()
  }
  const { controller, calls } = buildController([{}], { root })

  click(controller, { debounce: 10 })
  await wait(60) // well past the debounce window

  expect(calls()).toBe(0)
})

// --- reactive:applied -------------------------------------------------------

test("applied fires after renderStreamMessage with {action, params, html}", async () => {
  const html = '<turbo-stream action="replace" target="counter"><template></template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ body: html }], { root })
  const order = []
  globalThis.window.Turbo.renderStreamMessage = () => order.push("render")
  root.dispatchEvent = (event) => {
    root.events.push(event)
    if (event.type === "reactive:applied") order.push("applied")
  }

  await click(controller)

  const [event] = eventsNamed(root, "reactive:applied")
  expect(event).toBeDefined()
  expect(event.cancelable).toBe(false)
  expect(event.detail.action).toBe("save")
  expect(event.detail.params).toEqual({ n: 1 })
  expect(event.detail.html).toBe(html)
  // The stream was handed to Turbo BEFORE the event fired.
  expect(order).toEqual(["render", "applied"])
})

// --- reactive:error — kind mapping per failure branch -----------------------

test("a redirected response fires reactive:error kind=redirected", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ redirected: true, status: 200 }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("redirected")
  expect(event.detail.action).toBe("save")
  expect(typeof event.detail.retry).toBe("function")
})

test("a non-OK response fires reactive:error kind=http with status and body", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ ok: false, status: 403, body: "denied" }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("http")
  expect(event.detail.status).toBe(403)
  expect(event.detail.body).toBe("denied")
})

test("a non-turbo-stream response fires reactive:error kind=content-type", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ contentType: "text/html" }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("content-type")
})

test("a network failure fires reactive:error kind=network (console.error kept)", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ reject: new Error("offline") }], { root })
  const errors = []
  const original = console.error
  console.error = (...args) => errors.push(args)

  try {
    await click(controller)
  } finally {
    console.error = original
  }

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("network")
  // The existing console.error is unconditional — the event ADDS a hook, it
  // does not replace the log.
  expect(errors.length).toBe(1)
})

// A throw AFTER a successful fetch (token extraction, Turbo rendering, or a
// throwing reactive:applied listener) must NOT be labeled "network" — the
// server already processed the mutation, so a retry() there would re-POST an
// already-completed, potentially non-idempotent action (CodeRabbit review on
// PR #89). It fires kind="apply" with NO retry() in the detail at all.
test("a post-response render failure fires reactive:error kind=apply, NOT network, with no retry()", async () => {
  const html = '<turbo-stream action="replace" target="counter"><template></template></turbo-stream>'
  const root = makeRoot()
  const { controller } = buildController([{ body: html }], { root })
  globalThis.window.Turbo.renderStreamMessage = () => {
    throw new Error("Turbo choked on the stream")
  }

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("apply")
  expect(event.detail.retry).toBeUndefined()
})

// A throwing reactive:applied LISTENER is the same class of bug: the action
// already succeeded server-side, so this must not surface as retriable.
test("a throwing reactive:applied listener fires reactive:error kind=apply, not network", async () => {
  const html = '<turbo-stream action="replace" target="counter"><template></template></turbo-stream>'
  const root = makeRoot()
  root.dispatchEvent = (event) => {
    root.events.push(event)
    if (event.type === "reactive:applied") throw new Error("listener exploded")
  }
  const { controller } = buildController([{ body: html }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("apply")
})

// --- retry() ----------------------------------------------------------------

test("retry() re-enters the queue and does NOT refire before-dispatch", async () => {
  const root = makeRoot()
  // First fetch fails (500), the retried one succeeds.
  const { controller, calls } = buildController([{ ok: false, status: 500 }, {}], { root })

  await click(controller)
  expect(calls()).toBe(1)

  const [event] = eventsNamed(root, "reactive:error")
  await event.detail.retry()

  expect(calls()).toBe(2)
  // retry() is a queue re-entry, not a new user gesture — ONE before-dispatch.
  expect(eventsNamed(root, "reactive:before-dispatch").length).toBe(1)
})

test("retry() no-ops with a console.warn when the root left the DOM", async () => {
  const root = makeRoot()
  const { controller, calls } = buildController([{ ok: false, status: 500 }], { root })

  await click(controller)
  const [event] = eventsNamed(root, "reactive:error")

  root.isConnected = false // a plain replace detached this node
  const warnings = []
  const original = console.warn
  console.warn = (...args) => warnings.push(args)
  try {
    await event.detail.retry()
  } finally {
    console.warn = original
  }

  expect(calls()).toBe(1) // nothing re-enqueued
  expect(warnings.length).toBe(1)
})

// --- detached-root fallback ---------------------------------------------------

test("events from a detached root dispatch on document instead", async () => {
  const root = makeRoot({ connected: false })
  const { controller, documentEvents } = buildController([{ ok: false, status: 500 }], { root })

  await click(controller)

  expect(root.events.length).toBe(0)
  const names = documentEvents.map((event) => event.type)
  expect(names).toContain("reactive:before-dispatch")
  expect(names).toContain("reactive:error")
})
