// Unit tests for connect-time compute seeding (issue #199) — a freshly-rendered
// reactive_compute root SELF-SEEDS its derived fields on connect, so the outputs
// and cross-root mirrors are correct on first paint with NO synthetic `input`
// dispatched by the app.
//
// Before this, a compute root computed nothing until the first user `input`.
// Apps worked around it by dispatching a synthetic seed `input` on connect, but
// the compute root is a separate Stimulus controller that may connect a frame
// later, so the seed raced its own wiring — the classic symptom being a PARTIAL
// apply (an early output paints, a later output + the mirror stay blank).
//
// The fix: connect() runs ONE full recompute() (no event) when the root carries
// the compute binding + the seed marker, so the whole single-pass write set
// (issue #183) runs synchronously AFTER the controller is fully connected —
// every declared output + text sink + cross-root mirror painted from one reducer
// result. A turbo:morph-element re-seeds (the show/filter/dirty precedent). It is
// client-only: no round trip, and it is idempotent (change-guarded writes make a
// second pass a no-op, so an app still dispatching a synthetic input is fine).
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

let ReactiveController
let computeModule

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
  computeModule = await import("../../app/javascript/phlex/reactive/compute.js")
})

// A named form control faithful to REAL DOM semantics: a programmatic .value
// write coerces to String and fires NOTHING (browsers never fire `input` on a
// programmatic assignment — issue #76). closest() returns the owning root so
// #ownsField (issue #15) treats it as owned.
function makeField(name, value) {
  const listeners = []
  return {
    name,
    tagName: "INPUT",
    _root: null,
    _value: String(value),
    get value() {
      return this._value
    },
    set value(v) {
      this._value = String(v)
    },
    closest() {
      return this._root
    },
    getAttribute() {
      return null
    },
    addEventListener: (type, fn) => type === "input" && listeners.push(fn),
    dispatchEvent(event) {
      Object.defineProperty(event, "target", { value: this, configurable: true })
      if (event.type === "input") listeners.slice().forEach((fn) => fn(event))
      return true
    },
  }
}

// An owned reactive_text(:name) sink: a node carrying data-reactive-text="<name>"
// that #mirrorText writes textContent into. closest() points at the root so
// #ownsField sees it as owned.
function makeTextNode(name, text = "") {
  return {
    _root: null,
    _name: name,
    textContent: text,
    getAttribute(k) {
      return k === "data-reactive-text" ? this._name : null
    },
    closest() {
      return this._root
    },
  }
}

// A cross-root recap node (issue #159): lives OUTSIDE the root, resolved via the
// document stub, painted via textContent.
function makeRecapNode(text = "") {
  return { textContent: text }
}

// A compute root carrying the binding descriptors, the seed marker, and (given)
// the mirror param. It answers [name="X"] and [data-reactive-text="X"] queries
// over the supplied fields/text nodes, tracks listeners for the connect wiring,
// and can emit() a turbo:morph-element.
function makeRoot({ reducer, inputs, outputs, mirror, seed = true, fields = {}, textNodes = {} }) {
  const attrs = {
    "data-controller": "reactive",
    "data-action": "input->reactive#recompute",
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  if (seed) attrs["data-reactive-compute-seed"] = "true"
  if (mirror !== undefined) {
    attrs["data-reactive-compute-mirror-param"] = typeof mirror === "string" ? mirror : JSON.stringify(mirror)
  }
  const listeners = {}
  const root = {
    id: "sums",
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      const byName = sel.match(/\[name="(.+?)"\]/)
      if (byName) {
        const f = fields[byName[1]]
        return f ? [f] : []
      }
      const byText = sel.match(/\[data-reactive-text="(.+?)"\]/)
      if (byText) {
        const t = textNodes[byText[1]]
        return t ? [t] : []
      }
      return []
    },
    closest: () => null,
    matches: () => false,
    addEventListener: (name, fn) => (listeners[name] ??= []).push(fn),
    removeEventListener: (name, fn) => (listeners[name] = (listeners[name] ?? []).filter((f) => f !== fn)),
    emit: (name, event = {}) => (listeners[name] ?? []).forEach((fn) => fn({ type: name, ...event })),
    listeners,
  }
  for (const f of Object.values(fields)) f._root = root
  for (const t of Object.values(textNodes)) t._root = root
  return root
}

// Controller + a document stub answering id selectors from a map, and a window
// stub (connect() reads neither for compute, but other connect() probes touch
// them). Returns [controller, root].
function buildController(root, { documentMatches = {} } = {}) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.window ??= { addEventListener: () => {}, removeEventListener: () => {} }
  globalThis.document = {
    querySelector: () => null,
    querySelectorAll: (sel) => documentMatches[sel] ?? [],
    dispatchEvent: () => {},
  }
  return controller
}

beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

// --- the core regression: a full paint from ONE connect-time pass --------------

test("connect() self-seeds ALL outputs + the mirror from one reducer result", () => {
  // The issue's exact repro shape: two numeric outputs + a text mirror, a reducer
  // that returns every key each pass.
  const fields = {
    a: makeField("a", 2),
    b: makeField("b", 4),
    total: makeField("total", ""),
    half: makeField("half", ""),
  }
  const label = makeRecapNode("")
  computeModule.setComputeReducer("sums", ({ a, b }) => {
    const total = Number(a) + Number(b)
    return { total, half: total / 2, total_label: `${total}` }
  })
  const root = makeRoot({
    reducer: "sums",
    inputs: ["a", "b"],
    outputs: ["total", "half"],
    mirror: { total_label: ["#total-label"] },
    fields,
  })

  buildController(root, { documentMatches: { "#total-label": [label] } }).connect()

  // BOTH outputs painted — the early one AND the later one — from the seed pass.
  expect(fields.total.value).toBe("6")
  expect(fields.half.value).toBe("3")
  // And the cross-root mirror painted too — not left blank.
  expect(label.textContent).toBe("6")
})

test("connect() seeds an owned reactive_text sink (not just fields)", () => {
  const fields = { a: makeField("a", 10), b: makeField("b", 5), total: makeField("total", "") }
  const totalText = makeTextNode("total", "")
  computeModule.setComputeReducer("sums", ({ a, b }) => ({ total: Number(a) + Number(b) }))
  const root = makeRoot({
    reducer: "sums",
    inputs: ["a", "b"],
    outputs: ["total"],
    fields,
    textNodes: { total: totalText },
  })

  buildController(root).connect()

  expect(fields.total.value).toBe("15")
  expect(totalText.textContent).toBe("15")
})

// --- gating: no marker, no reducer, morph, idempotence -------------------------

test("connect() does NOT self-seed a root without the seed marker", () => {
  const fields = { a: makeField("a", 2), b: makeField("b", 4), total: makeField("total", "") }
  computeModule.setComputeReducer("sums", ({ a, b }) => ({ total: Number(a) + Number(b) }))
  const root = makeRoot({ reducer: "sums", inputs: ["a", "b"], outputs: ["total"], seed: false, fields })

  buildController(root).connect()

  // Marker absent → connect leaves the derived field at its (blank) render value.
  expect(fields.total.value).toBe("")
})

test("connect() self-seed is a no-op (no throw) when no reducer is registered", () => {
  const fields = { a: makeField("a", 2), total: makeField("total", "") }
  const root = makeRoot({ reducer: "missing", inputs: ["a"], outputs: ["total"], fields })

  expect(() => buildController(root).connect()).not.toThrow()
  expect(fields.total.value).toBe("")
})

test("a turbo:morph-element re-seeds the outputs", () => {
  const fields = { a: makeField("a", 3), b: makeField("b", 3), total: makeField("total", "") }
  computeModule.setComputeReducer("sums", ({ a, b }) => ({ total: Number(a) + Number(b) }))
  const root = makeRoot({ reducer: "sums", inputs: ["a", "b"], outputs: ["total"], fields })

  buildController(root).connect()
  expect(fields.total.value).toBe("6")

  // An in-place morph re-rendered the output blank (server truth for a fresh
  // draft) while keeping the element connected — the post-morph re-seed refills.
  fields.total.value = ""
  root.emit("turbo:morph-element", { target: root })
  expect(fields.total.value).toBe("6")
})

test("connect() self-seed threads no round trip (never enqueues)", () => {
  const fields = { a: makeField("a", 2), b: makeField("b", 4), total: makeField("total", "") }
  computeModule.setComputeReducer("sums", ({ a, b }) => ({ total: Number(a) + Number(b) }))
  const root = makeRoot({ reducer: "sums", inputs: ["a", "b"], outputs: ["total"], fields })

  const controller = buildController(root)
  let dispatched = 0
  controller.dispatch = () => (dispatched += 1)
  controller.connect()

  expect(fields.total.value).toBe("6")
  expect(dispatched).toBe(0)
})

test("disconnect() removes the compute seed morph listener", () => {
  const fields = { a: makeField("a", 1), total: makeField("total", "") }
  computeModule.setComputeReducer("sums", ({ a }) => ({ total: Number(a) }))
  const root = makeRoot({ reducer: "sums", inputs: ["a"], outputs: ["total"], fields })

  const controller = buildController(root)
  controller.connect()
  controller.disconnect()

  expect(root.listeners["turbo:morph-element"] ?? []).toHaveLength(0)
})
