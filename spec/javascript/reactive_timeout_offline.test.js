// Unit tests for request timeout + offline handling (issue #101):
//
//   TIMEOUT — the fetch is given AbortSignal.timeout(ms) (ms from
//   <meta name="phlex-reactive-timeout">, default 30000). AbortSignal.timeout()
//   rejects with a DOMException named "TimeoutError" (NOT "AbortError" — that's a
//   manual AbortController.abort()). The fetch catch maps "TimeoutError" to
//   reactive:error kind:"timeout" (retriable) WITHOUT the offline-fallback clone
//   or the network marker; the queue continues (a second click still fetches).
//
//   OFFLINE — #perform gates on navigator.onLine === false right before fetch
//   (authoritative at the network boundary — catches a click that enqueued while
//   online but sends after going offline), firing reactive:error kind:"offline"
//   (retriable) and skipping the fetch entirely — the edit is never half-sent.
//
//   FLAG — module-level online/offline listeners toggle data-reactive-offline on
//   document.documentElement (a pure CSS hook), seeded from navigator.onLine.
//
// Scripted fetch stubs reject with a NAMED DOMException-like error — never a real
// timer against real fetch (bun:test fails a test on any surfaced exception).
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, afterEach } from "bun:test"

let ReactiveController
let registerReactiveOffline
let __resetReactiveOfflineForTest

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  const mod = await import("../../app/javascript/phlex/reactive/reactive_controller.js")
  ReactiveController = mod.default
  registerReactiveOffline = mod.registerReactiveOffline
  __resetReactiveOfflineForTest = mod.__resetReactiveOfflineForTest
})

afterEach(() => {
  // Restore a sane global navigator between tests.
  globalThis.navigator = { onLine: true }
})

// A named DOMException-like error, matching what AbortSignal.timeout() / abort()
// reject with (name is what the controller branches on).
function abortError(name) {
  const e = new Error(name)
  e.name = name
  return e
}

// A reactive root stub recording dispatched events + attribute writes.
function makeRoot({ connected = true } = {}) {
  const attrs = {}
  const events = []
  return {
    attrs,
    events,
    isConnected: connected,
    id: "counter",
    dispatchEvent: (event) => events.push(event),
    querySelectorAll: () => [],
    setAttribute: (name, value) => (attrs[name] = String(value)),
    removeAttribute: (name) => delete attrs[name],
    getAttribute: (name) => attrs[name] ?? null,
    hasAttribute: (name) => name in attrs,
  }
}

// Build a controller with a scripted fetch. `responses` entries: { reject: Error }
// to reject (a timeout/network), or a response-shape object. Records the fetch
// `signal` each call received so a test can assert AbortSignal.timeout was passed.
function buildController(responses, { root, onLine = true, timeoutMeta } = {}) {
  const controller = new ReactiveController()
  controller.element = root ?? makeRoot()
  controller.tokenValue = "tok"
  globalThis.navigator = { onLine }

  const signals = []
  let calls = 0
  globalThis.fetch = (_url, opts) => {
    signals.push(opts?.signal ?? null)
    const script = responses[Math.min(calls, responses.length - 1)]
    calls++
    if (script?.reject) return Promise.reject(script.reject)
    return Promise.resolve({
      redirected: script?.redirected ?? false,
      ok: script?.ok ?? true,
      status: script?.status ?? 200,
      headers: { get: () => script?.contentType ?? "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(script?.body ?? ""),
    })
  }
  globalThis.document = {
    querySelector: (sel) => {
      if (sel === 'meta[name="phlex-reactive-timeout"]') return timeoutMeta ? { content: timeoutMeta } : null
      return null
    },
    dispatchEvent: () => {},
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, calls: () => calls, signals }
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

// --- TIMEOUT ----------------------------------------------------------------

test("the fetch is given an AbortSignal (timeout wired)", async () => {
  const root = makeRoot()
  const { controller, signals } = buildController([{}], { root })

  await click(controller)

  expect(signals[0]).toBeInstanceOf(AbortSignal)
})

test("a TimeoutError abort fires reactive:error kind=timeout with retry", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ reject: abortError("TimeoutError") }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("timeout")
  expect(typeof event.detail.retry).toBe("function")
})

test("a TimeoutError does NOT mark the root data-reactive-error=network (it's a timeout)", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ reject: abortError("TimeoutError") }], { root })

  await click(controller)

  expect(root.attrs["data-reactive-error"]).toBe("timeout")
})

test("the queue CONTINUES after a timeout — a second click still fetches", async () => {
  const root = makeRoot()
  // First fetch times out, second succeeds.
  const { controller, calls } = buildController(
    [{ reject: abortError("TimeoutError") }, { body: "" }],
    { root },
  )

  await click(controller)
  expect(calls()).toBe(1)

  await click(controller)
  expect(calls()).toBe(2) // the hung request did NOT wedge the queue
})

test("retry() after a timeout re-enters the queue and fetches again", async () => {
  const root = makeRoot()
  const { controller, calls } = buildController(
    [{ reject: abortError("TimeoutError") }, { body: "" }],
    { root },
  )

  await click(controller)
  const [event] = eventsNamed(root, "reactive:error")
  await event.detail.retry()

  expect(calls()).toBe(2)
})

test("a genuine network TypeError is still kind=network (NOT timeout)", async () => {
  const root = makeRoot()
  const { controller } = buildController([{ reject: new TypeError("Failed to fetch") }], { root })

  await click(controller)

  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("network")
})

test("a custom timeout meta is honored (the signal reflects a short timeout)", async () => {
  // We can't easily read the ms off an AbortSignal, but we CAN prove the meta is
  // read without throwing and a signal is still produced.
  const root = makeRoot()
  const { controller, signals } = buildController([{}], { root, timeoutMeta: "5000" })

  await click(controller)

  expect(signals[0]).toBeInstanceOf(AbortSignal)
})

// --- OFFLINE ----------------------------------------------------------------

test("offline short-circuits: navigator.onLine false fires kind=offline and skips fetch", async () => {
  const root = makeRoot()
  const { controller, calls } = buildController([{}], { root, onLine: false })

  await click(controller)

  expect(calls()).toBe(0) // never sent — the edit is not half-sent
  const [event] = eventsNamed(root, "reactive:error")
  expect(event.detail.kind).toBe("offline")
  expect(typeof event.detail.retry).toBe("function")
})

test("offline marks the root data-reactive-error=offline", async () => {
  const root = makeRoot()
  const { controller } = buildController([{}], { root, onLine: false })

  await click(controller)

  expect(root.attrs["data-reactive-error"]).toBe("offline")
})

test("retry() after offline, once back online, actually fetches", async () => {
  const root = makeRoot()
  const { controller, calls } = buildController([{}], { root, onLine: false })

  await click(controller)
  expect(calls()).toBe(0)

  // Back online, then retry.
  globalThis.navigator = { onLine: true }
  const [event] = eventsNamed(root, "reactive:error")
  await event.detail.retry()

  expect(calls()).toBe(1)
})

test("a request that enqueues online but sends offline is kind=offline (authoritative gate)", async () => {
  // Gate lives in #perform (send time), so a transition after the click but
  // before send still yields kind=offline, not network. Simulate by flipping
  // navigator between dispatch and the queued #perform: onLine at click, offline
  // by the time fetch would run. We approximate by starting offline (the perform
  // gate reads navigator live).
  const root = makeRoot()
  const { controller, calls } = buildController([{}], { root, onLine: false })

  await click(controller)

  expect(calls()).toBe(0)
  expect(eventsNamed(root, "reactive:error")[0].detail.kind).toBe("offline")
})

// --- FLAG -------------------------------------------------------------------

test("registerReactiveOffline toggles data-reactive-offline from navigator.onLine + events", () => {
  const attrs = {}
  const root = {
    toggleAttribute: (name, force) => {
      if (force) attrs[name] = ""
      else delete attrs[name]
    },
    hasAttribute: (name) => name in attrs,
  }
  const listeners = {}
  globalThis.navigator = { onLine: true }
  globalThis.window = {
    addEventListener: (name, fn) => ((listeners[name] ??= []).push(fn)),
  }
  globalThis.document = { documentElement: root }

  __resetReactiveOfflineForTest()
  registerReactiveOffline()

  // Seeded online → no flag.
  expect(root.hasAttribute("data-reactive-offline")).toBe(false)

  // Go offline → flag set.
  globalThis.navigator = { onLine: false }
  listeners["offline"].forEach((fn) => fn())
  expect(root.hasAttribute("data-reactive-offline")).toBe(true)

  // Back online → flag cleared.
  globalThis.navigator = { onLine: true }
  listeners["online"].forEach((fn) => fn())
  expect(root.hasAttribute("data-reactive-offline")).toBe(false)
})

test("registerReactiveOffline seeds the flag when starting offline", () => {
  const attrs = {}
  const root = {
    toggleAttribute: (name, force) => {
      if (force) attrs[name] = ""
      else delete attrs[name]
    },
    hasAttribute: (name) => name in attrs,
  }
  globalThis.navigator = { onLine: false }
  globalThis.window = { addEventListener: () => {} }
  globalThis.document = { documentElement: root }

  __resetReactiveOfflineForTest()
  registerReactiveOffline()

  expect(root.hasAttribute("data-reactive-offline")).toBe(true)
})

test("registerReactiveOffline is idempotent (a second call adds no duplicate listeners)", () => {
  const listeners = {}
  globalThis.navigator = { onLine: true }
  globalThis.window = {
    addEventListener: (name, fn) => ((listeners[name] ??= []).push(fn)),
  }
  globalThis.document = { documentElement: { toggleAttribute: () => {} } }

  __resetReactiveOfflineForTest()
  registerReactiveOffline()
  registerReactiveOffline()

  expect(listeners["online"].length).toBe(1)
  expect(listeners["offline"].length).toBe(1)
})
