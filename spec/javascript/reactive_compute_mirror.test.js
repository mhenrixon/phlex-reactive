// Unit tests for cross-root compute mirrors (issue #159) — the DECLARED escape
// from root isolation (issue #15) for a derived value shown in a recap OUTSIDE
// the computing root:
//
//   * The root carries data-reactive-compute-mirror-param — a JSON object of
//     { name: [id selectors] } emitted by reactive_compute's `mirror:`.
//   * AFTER the outputs are applied, every declared mirror name is painted into
//     its document-wide id targets via textContent (XSS-safe, change-guarded).
//     The value is the reducer's result when it produced one, else the owned
//     field's current value (an input identity mirror / a just-written output).
//   * A name with NO value this pass is skipped — a mirror never blanks.
//   * Targets are id selectors ONLY — the client re-checks the shape the server
//     validated at declare time (two-sided default-deny); anything else is
//     warn-and-skipped.
//   * Malformed/absent mirror attrs degrade to no mirror — never a throw.
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

// A named form control (same stand-in as reactive_text_compute.test.js).
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

// A cross-root recap node: it lives OUTSIDE the computing root (resolved via
// document.getElementById-style lookup, not the root's querySelectorAll).
function makeRecapNode(text = "") {
  return { textContent: text }
}

// A compute root that also carries the mirror param when given.
function makeRoot({ reducer, inputs, outputs, mirror, fields = {} }) {
  const attrs = {
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  if (mirror !== undefined) {
    attrs["data-reactive-compute-mirror-param"] = typeof mirror === "string" ? mirror : JSON.stringify(mirror)
  }
  const root = {
    id: "editor",
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      const m = sel.match(/\[name="(.+?)"\]/)
      if (m) {
        const f = fields[m[1]]
        return f ? [f] : []
      }
      return []
    },
    closest: () => null,
  }
  for (const f of Object.values(fields)) f._root = root
  return root
}

// The controller + a document stub answering id selectors from a map. Returns
// [controller, queried] — `queried` records every selector the document saw.
function buildController(root, { documentMatches = {} } = {}) {
  const controller = new ReactiveController()
  controller.element = root
  const queried = []
  globalThis.window ??= {}
  globalThis.document = {
    querySelectorAll: (sel) => {
      queried.push(sel)
      return documentMatches[sel] ?? []
    },
  }
  return [controller, queried]
}

beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

// --- the reducer-result path --------------------------------------------------

test("a reducer-result key declared in mirror: paints its document-wide target", () => {
  const fields = { a: makeField("a", "100"), b: makeField("b", "380") }
  const recap = makeRecapNode()
  computeModule.setComputeReducer("split", ({ a, b }) => ({ sum_total: a + b }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a", "b"],
      outputs: [],
      mirror: { sum_total: ["#sum_total"] },
      fields,
    }),
    { documentMatches: { "#sum_total": [recap] } },
  )
  controller.recompute({ target: fields.a })

  expect(recap.textContent).toBe("480")
})

test("every declared selector for one name is painted", () => {
  const fields = { a: makeField("a", "7") }
  const one = makeRecapNode()
  const two = makeRecapNode()
  computeModule.setComputeReducer("split", ({ a }) => ({ doubled: a * 2 }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { doubled: ["#recap", "#footer-recap"] },
      fields,
    }),
    { documentMatches: { "#recap": [one], "#footer-recap": [two] } },
  )
  controller.recompute({ target: fields.a })

  expect(one.textContent).toBe("14")
  expect(two.textContent).toBe("14")
})

test("an output that wrote a FIELD also paints its declared mirror target", () => {
  const fields = { a: makeField("a", "100"), cash: makeField("cash", "0") }
  const recap = makeRecapNode()
  computeModule.setComputeReducer("split", ({ a }) => ({ cash: 500 - a }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: ["cash"],
      mirror: { cash: ["#summary-cash"] },
      fields,
    }),
    { documentMatches: { "#summary-cash": [recap] } },
  )
  controller.recompute({ target: fields.a })

  expect(fields.cash.value).toBe("400") // the field write still happened
  expect(recap.textContent).toBe("400") // and the recap mirrors it
})

// --- the identity path (no reducer needed) -------------------------------------

test("a mirror keyed on a declared INPUT paints its identity value with NO reducer", () => {
  const fields = { cash: makeField("cash", "250") }
  const recap = makeRecapNode()
  // No setComputeReducer call — the identity pass still feeds the mirror.

  const [controller] = buildController(
    makeRoot({
      reducer: "none",
      inputs: ["cash"],
      outputs: [],
      mirror: { cash: ["#summary-cash"] },
      fields,
    }),
    { documentMatches: { "#summary-cash": [recap] } },
  )
  controller.recompute({ target: fields.cash })

  expect(recap.textContent).toBe("250")
})

// --- never blank, change-guarded ----------------------------------------------

test("a mirror name with NO value this pass is skipped (never blanks the recap)", () => {
  const fields = { a: makeField("a", "1") }
  const recap = makeRecapNode("keep")
  computeModule.setComputeReducer("split", () => ({})) // reducer returns nothing

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { sum_total: ["#sum_total"] },
      fields,
    }),
    { documentMatches: { "#sum_total": [recap] } },
  )
  controller.recompute({ target: fields.a })

  expect(recap.textContent).toBe("keep")
})

test("the cross-root write is change-guarded (unchanged value → no write)", () => {
  const fields = { a: makeField("a", "480") }
  const recap = makeRecapNode()
  let writes = 0
  Object.defineProperty(recap, "textContent", {
    get() {
      return this._t ?? "480"
    },
    set(v) {
      writes++
      this._t = v
    },
  })
  computeModule.setComputeReducer("split", ({ a }) => ({ sum_total: a }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { sum_total: ["#sum_total"] },
      fields,
    }),
    { documentMatches: { "#sum_total": [recap] } },
  )
  controller.recompute({ target: fields.a })

  expect(writes).toBe(0)
})

// --- the allowlist (two-sided default-deny; client side warns + skips) ---------

test("a non-id selector in a hand-built mirror attr is refused (warn + skip)", () => {
  const fields = { a: makeField("a", "1") }
  computeModule.setComputeReducer("split", ({ a }) => ({ sum: a }))

  const [controller, queried] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { sum: ["[data-x]", ".totals", "*", "#x .y"] },
      fields,
    }),
  )
  const warns = []
  const original = console.warn
  console.warn = (...args) => warns.push(args.join(" "))

  try {
    controller.recompute({ target: fields.a })
  } finally {
    console.warn = original
  }

  expect(warns.length).toBe(4) // each refused selector warns
  expect(queried).toEqual([]) // the document was never consulted for them
})

test("a refused selector does not take down its siblings (the id target still paints)", () => {
  const fields = { a: makeField("a", "9") }
  const recap = makeRecapNode()
  computeModule.setComputeReducer("split", ({ a }) => ({ sum: a }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { sum: ["[data-x]", "#sum"] },
      fields,
    }),
    { documentMatches: { "#sum": [recap] } },
  )
  const original = console.warn
  console.warn = () => {}

  try {
    controller.recompute({ target: fields.a })
  } finally {
    console.warn = original
  }

  expect(recap.textContent).toBe("9")
})

// --- resilience -----------------------------------------------------------------

test("a malformed mirror attr degrades to no mirror (never throws)", () => {
  const fields = { a: makeField("a", "1") }
  computeModule.setComputeReducer("split", ({ a }) => ({ sum: a }))

  for (const bad of ["not json", "[]", "42", '"str"']) {
    const [controller] = buildController(
      makeRoot({ reducer: "split", inputs: ["a"], outputs: [], mirror: bad, fields }),
    )
    expect(() => controller.recompute({ target: fields.a })).not.toThrow()
  }
})

test("a missing target element is a no-op (recap not yet in the DOM)", () => {
  const fields = { a: makeField("a", "1") }
  computeModule.setComputeReducer("split", ({ a }) => ({ sum: a }))

  const [controller] = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["a"],
      outputs: [],
      mirror: { sum: ["#gone"] },
      fields,
    }),
  )

  expect(() => controller.recompute({ target: fields.a })).not.toThrow()
})

test("NO mirror declared: the document is never consulted (the shipped path is untouched)", () => {
  const fields = { a: makeField("a", "1") }
  computeModule.setComputeReducer("split", ({ a }) => ({ sum: a }))

  const [controller, queried] = buildController(
    makeRoot({ reducer: "split", inputs: ["a"], outputs: [], fields }),
  )
  controller.recompute({ target: fields.a })

  expect(queried).toEqual([])
})
