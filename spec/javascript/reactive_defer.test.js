// Unit tests for the `reactive:defer` custom Turbo StreamAction (issue #165) —
// the client half of deferred reply segments. The server emits
//
//   <turbo-stream action="reactive:defer" target="<id>"
//                 data-reactive-defer-via="fetch"
//                 data-reactive-defer-token="<signed>"></turbo-stream>
//
// and the handler must:
//   * mark the target pending (data-reactive-defer-pending + aria-busy),
//   * POST the token to the defer endpoint OFF the per-controller action queue
//     (a module-level fetch — the whole point is not blocking the next action),
//   * apply the arriving turbo-stream ONLY if this defer is still current
//     (supersession: a newer directive for the same target aborts the older),
//   * clear pending on 204 (render? false — keep content),
//   * mark data-reactive-error="defer" + emit reactive:error (with retry) on
//     failure,
//   * on the push lane (via="stream"), insert a <pgbus-stream-source> whose
//     removal is the broadcast's own job (the payload carries the remove).
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

let registerReactiveDefer
let resetReactiveDefers

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  const mod = await import("../../app/javascript/phlex/reactive/reactive_controller.js")
  registerReactiveDefer = mod.registerReactiveDefer
  resetReactiveDefers = mod.resetReactiveDefers
})

beforeEach(() => {
  resetReactiveDefers()
})

// A controllable promise, so tests decide exactly when a fetch settles.
function deferred() {
  let resolve, reject
  const promise = new Promise((res, rej) => ((resolve = res), (reject = rej)))
  return { promise, resolve, reject }
}

function makeTargetEl(id) {
  const el = {
    id,
    attrs: {},
    dispatched: [],
    setAttribute(name, value) {
      el.attrs[name] = value
    },
    removeAttribute(name) {
      delete el.attrs[name]
    },
    getAttribute(name) {
      return el.attrs[name] ?? null
    },
    dispatchEvent(event) {
      el.dispatched.push(event)
    },
  }
  return el
}

// Fake document: getElementById from a map, querySelector for metas, plus
// createElement/body.appendChild recording for the stream lane.
function stubDocument({ byId = {}, metas = {} } = {}) {
  const created = []
  const appended = []
  globalThis.document = {
    getElementById: (id) => byId[id] ?? null,
    querySelector: (sel) => {
      const name = sel.match(/meta\[name="([^"]+)"\]/)?.[1]
      return name && metas[name] != null ? { content: metas[name] } : null
    },
    createElement: (tag) => {
      const el = makeTargetEl(null)
      el.tagName = tag
      el.removed = false
      el.remove = () => {
        el.removed = true
      }
      created.push(el)
      return el
    },
    body: { appendChild: (el) => appended.push(el) },
  }
  return { created, appended }
}

function stubTurbo() {
  const rendered = []
  globalThis.window = {
    Turbo: {
      StreamActions: {},
      renderStreamMessage: (html) => rendered.push(html),
    },
  }
  return { actions: globalThis.window.Turbo.StreamActions, rendered }
}

function stubFetch() {
  const calls = []
  globalThis.fetch = (url, options) => {
    const gate = deferred()
    calls.push({ url, options, gate })
    return gate.promise
  }
  return calls
}

// A fake <turbo-stream action="reactive:defer"> element.
function directiveEl({ target, token = "signed-defer-token", via = "fetch", src, sinceId } = {}) {
  const attrs = { target, "data-reactive-defer-via": via }
  if (token != null) attrs["data-reactive-defer-token"] = token
  if (src != null) attrs["data-reactive-defer-src"] = src
  if (sinceId != null) attrs["data-reactive-defer-since-id"] = sinceId
  return { getAttribute: (name) => attrs[name] ?? null }
}

function okResponse(html) {
  return {
    ok: true,
    status: 200,
    headers: { get: () => "text/vnd.turbo-stream.html" },
    text: () => Promise.resolve(html),
  }
}

// Drain enough microtasks for the async fetch pipeline to advance.
async function flush(times = 6) {
  for (let i = 0; i < times; i++) await Promise.resolve()
}

test("registers reactive:defer once (idempotent)", () => {
  const { actions } = stubTurbo()
  registerReactiveDefer()
  const first = actions["reactive:defer"]
  registerReactiveDefer()
  expect(actions["reactive:defer"]).toBe(first)
  expect(typeof first).toBe("function")
})

test("fetch lane: marks pending, POSTs the token to the defer path, applies the arrival", async () => {
  const { actions, rendered } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el }, metas: { "csrf-token": "csrf-123" } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals" }))

  // Pending markers land synchronously — the shimmer window opens immediately.
  expect(el.attrs["data-reactive-defer-pending"]).toBe("true")
  expect(el.attrs["aria-busy"]).toBe("true")

  expect(calls.length).toBe(1)
  expect(calls[0].url).toBe("/reactive/defer")
  expect(calls[0].options.method).toBe("POST")
  expect(calls[0].options.headers["Accept"]).toBe("text/vnd.turbo-stream.html")
  expect(calls[0].options.headers["X-CSRF-Token"]).toBe("csrf-123")
  expect(JSON.parse(calls[0].options.body)).toEqual({ token: "signed-defer-token" })

  calls[0].gate.resolve(okResponse("<turbo-stream><template>real</template></turbo-stream>"))
  await flush()

  expect(rendered).toEqual(["<turbo-stream><template>real</template></turbo-stream>"])
  expect(el.attrs["data-reactive-defer-pending"]).toBeUndefined()
  expect(el.attrs["aria-busy"]).toBeUndefined()
})

test("honors a <meta name=\"phlex-reactive-defer-path\"> override", () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el }, metas: { "phlex-reactive-defer-path": "/custom/defer" } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals" }))
  expect(calls[0].url).toBe("/custom/defer")
})

test("a missing target is a warn-and-skip (no fetch)", () => {
  const { actions } = stubTurbo()
  stubDocument({ byId: {} })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "ghost" }))
  expect(calls.length).toBe(0)
})

test("supersession: a newer directive for the SAME target aborts the older fetch and its late arrival is discarded", async () => {
  const { actions, rendered } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals", token: "first" }))
  actions["reactive:defer"].call(directiveEl({ target: "slow-totals", token: "second" }))

  expect(calls.length).toBe(2)
  expect(calls[0].options.signal.aborted).toBe(true)
  expect(calls[1].options.signal.aborted).toBe(false)

  // The FIRST (stale) response resolving late must never paint.
  calls[0].gate.resolve(okResponse("<turbo-stream><template>stale</template></turbo-stream>"))
  await flush()
  expect(rendered).toEqual([])

  calls[1].gate.resolve(okResponse("<turbo-stream><template>fresh</template></turbo-stream>"))
  await flush()
  expect(rendered).toEqual(["<turbo-stream><template>fresh</template></turbo-stream>"])
})

test("independent targets defer in parallel — one does not supersede the other", async () => {
  const { actions, rendered } = stubTurbo()
  const totals = makeTargetEl("totals")
  const chart = makeTargetEl("chart")
  stubDocument({ byId: { totals, chart } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "totals" }))
  actions["reactive:defer"].call(directiveEl({ target: "chart" }))

  expect(calls[0].options.signal.aborted).toBe(false)
  expect(calls[1].options.signal.aborted).toBe(false)

  calls[0].gate.resolve(okResponse("<t1/>"))
  calls[1].gate.resolve(okResponse("<t2/>"))
  await flush()
  expect(rendered).toEqual(["<t1/>", "<t2/>"])
})

test("204 (render? false) clears pending and applies nothing", async () => {
  const { actions, rendered } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals" }))
  calls[0].gate.resolve({ ok: true, status: 204, headers: { get: () => "" }, text: () => Promise.resolve("") })
  await flush()

  expect(rendered).toEqual([])
  expect(el.attrs["data-reactive-defer-pending"]).toBeUndefined()
  expect(el.attrs["aria-busy"]).toBeUndefined()
})

test("an HTTP failure marks the target and emits reactive:error kind=defer with a retry", async () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals" }))
  calls[0].gate.resolve({ ok: false, status: 400, headers: { get: () => "" }, text: () => Promise.resolve("nope") })
  await flush()

  expect(el.attrs["data-reactive-defer-pending"]).toBeUndefined()
  expect(el.attrs["data-reactive-error"]).toBe("defer")
  expect(el.dispatched.length).toBe(1)
  expect(el.dispatched[0].detail.kind).toBe("defer")
  expect(typeof el.dispatched[0].detail.retry).toBe("function")

  // retry() re-enters the defer fetch with the SAME token.
  el.dispatched[0].detail.retry()
  expect(calls.length).toBe(2)
  expect(JSON.parse(calls[1].options.body)).toEqual({ token: "signed-defer-token" })
})

test("a network failure (fetch rejects) also marks + emits, and a SUPERSEDED abort stays silent", async () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  stubDocument({ byId: { "slow-totals": el } })
  const calls = stubFetch()
  registerReactiveDefer()

  actions["reactive:defer"].call(directiveEl({ target: "slow-totals", token: "first" }))
  // Supersede — the first fetch aborts; its rejection must NOT mark an error.
  actions["reactive:defer"].call(directiveEl({ target: "slow-totals", token: "second" }))
  const abortError = new Error("aborted")
  abortError.name = "AbortError"
  calls[0].gate.reject(abortError)
  await flush()
  expect(el.attrs["data-reactive-error"]).toBeUndefined()
  expect(el.dispatched.length).toBe(0)

  // A REAL network failure on the current defer marks + emits.
  calls[1].gate.reject(new TypeError("network down"))
  await flush()
  expect(el.attrs["data-reactive-error"]).toBe("defer")
  expect(el.dispatched.length).toBe(1)
})

test("stream lane: inserts a pgbus-stream-source with the deterministic id, src and since-id", () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  const { appended } = stubDocument({ byId: { "slow-totals": el } })
  globalThis.customElements = { get: (name) => (name === "pgbus-stream-source" ? class {} : undefined) }
  registerReactiveDefer()

  actions["reactive:defer"].call(
    directiveEl({ target: "slow-totals", via: "stream", token: null, src: "/pgbus/streams/signed", sinceId: "0" }),
  )

  expect(el.attrs["data-reactive-defer-pending"]).toBe("true")
  expect(appended.length).toBe(1)
  const source = appended[0]
  expect(source.tagName).toBe("pgbus-stream-source")
  expect(source.id).toBe("reactive-defer-src-slow-totals")
  expect(source.attrs["src"]).toBe("/pgbus/streams/signed")
  expect(source.attrs["since-id"]).toBe("0")
})

test("stream lane: a newer stream directive removes the older source element (unsubscribe = supersede)", () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  const { appended } = stubDocument({ byId: { "slow-totals": el } })
  globalThis.customElements = { get: () => class {} }
  registerReactiveDefer()

  const directive = (src) =>
    directiveEl({ target: "slow-totals", via: "stream", token: null, src, sinceId: "0" })
  actions["reactive:defer"].call(directive("/pgbus/streams/one"))
  actions["reactive:defer"].call(directive("/pgbus/streams/two"))

  expect(appended.length).toBe(2)
  expect(appended[0].removed).toBe(true)
  expect(appended[1].removed).toBe(false)
})

test("stream lane: an unregistered pgbus element is a loud no-op (no insert, no throw)", () => {
  const { actions } = stubTurbo()
  const el = makeTargetEl("slow-totals")
  const { appended } = stubDocument({ byId: { "slow-totals": el } })
  globalThis.customElements = { get: () => undefined }
  registerReactiveDefer()

  actions["reactive:defer"].call(
    directiveEl({ target: "slow-totals", via: "stream", token: null, src: "/pgbus/streams/signed" }),
  )
  expect(appended.length).toBe(0)
})
