// Unit test for client-side computes (data bindings) — the "instant" half of
// the new/unpersisted-record UX.
//
// A component declares `reactive_compute :name, inputs:, outputs:` (Ruby) which
// emits data-reactive-compute-* on the root. A JS reducer registered under the
// reducer key runs on `input` — reading the named input fields, writing the
// named output fields — with NO round trip. The debounced POST (if the field
// also carries on(...)) reconciles from the server reply afterward.
//
// This mirrors confirm.js's settable-registry seam: setComputeReducer(key, fn)
// registers; the controller's #recompute looks it up and applies it.
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

// A fake named form control matching REAL DOM semantics: a programmatic .value
// write coerces to String and fires NOTHING (browsers never fire `input` on a
// programmatic assignment — issue #76). Listeners only run through an explicit
// dispatchEvent, which is what the controller must call itself. `closest`
// returns the owning root so #ownsField (issue #15) treats it as owned.
function makeField(name, value) {
  const listeners = []
  return {
    name,
    tagName: "INPUT",
    _root: null, // set by makeRoot so closest() can resolve ownership
    _value: String(value),
    get value() {
      return this._value
    },
    set value(v) {
      this._value = String(v) // real DOM: coerce only, NO events
    },
    closest() {
      return this._root
    },
    addEventListener: (type, fn) => type === "input" && listeners.push(fn),
    dispatchEvent(event) {
      if (event.type === "input") listeners.slice().forEach((fn) => fn(event))
      return true
    },
  }
}

// A root element carrying the compute config + a set of named fields. The
// controller reads inputs/outputs/reducer from the root's dataset-style getAttribute
// and finds fields by name via querySelectorAll('[name=...]').
function makeRoot({ reducer, inputs, outputs, fields }) {
  const attrs = {
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  const root = {
    id: "order",
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      const m = sel.match(/\[name="(.+?)"\]/)
      if (!m) return []
      const f = fields[m[1]]
      return f ? [f] : []
    },
    closest: () => null,
  }
  // Point each field's closest() at this root so #ownsField sees it as owned.
  for (const f of Object.values(fields)) f._root = root
  return root
}

function buildController(root) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.window ??= {}
  return controller
}

// Reset the registry between tests so a reducer registered in one test can't
// leak into the next.
beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

test("setComputeReducer registers a reducer looked up by key", () => {
  const fn = () => ({})
  computeModule.setComputeReducer("split", fn)
  expect(computeModule.computeReducer("split")).toBe(fn)
})

test("an unregistered key resolves to undefined (no throw)", () => {
  expect(computeModule.computeReducer("missing")).toBeUndefined()
})

test("#recompute runs the reducer over the input fields and writes the outputs", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 0),
    leasing: makeField("leasing", 0),
    total: makeField("total", 500),
  }
  computeModule.setComputeReducer("payment_split", ({ allowance, cash, leasing, total }) => {
    // trivial three-way split: cash absorbs the remainder
    return { allowance, leasing, cash: total - allowance - leasing }
  })

  const controller = buildController(
    makeRoot({
      reducer: "payment_split",
      inputs: ["allowance", "cash", "leasing", "total"],
      outputs: ["allowance", "cash", "leasing"],
      fields,
    }),
  )

  controller.recompute({ target: fields.allowance })

  // cash recomputed instantly, no network
  expect(fields.cash.value).toBe("400")
  // untouched peers keep their submitted values
  expect(fields.allowance.value).toBe("100")
  expect(fields.leasing.value).toBe("0")
})

test("#recompute coerces field values to numbers for the reducer", () => {
  const fields = {
    allowance: makeField("allowance", "100"),
    cash: makeField("cash", ""),
    leasing: makeField("leasing", ""),
    total: makeField("total", "500"),
  }
  let seen
  computeModule.setComputeReducer("payment_split", (values) => {
    seen = values
    return {}
  })

  const controller = buildController(
    makeRoot({
      reducer: "payment_split",
      inputs: ["allowance", "cash", "leasing", "total"],
      outputs: [],
      fields,
    }),
  )
  controller.recompute({ target: fields.allowance })

  // blank fields → 0, not NaN or "" (matches new_order_controller.js nanToZero)
  expect(seen).toEqual({ allowance: 100, cash: 0, leasing: 0, total: 500 })
})

test("#recompute is a no-op when no reducer is registered for the key", () => {
  const fields = { total: makeField("total", 500), cash: makeField("cash", 999) }
  const controller = buildController(
    makeRoot({ reducer: "unregistered", inputs: ["total"], outputs: ["cash"], fields }),
  )

  // must not throw, must not touch the outputs
  controller.recompute({ target: fields.total })
  expect(fields.cash.value).toBe("999")
})

test("a changed output write dispatches exactly one bubbling input event on the field", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 0),
    total: makeField("total", 500),
  }
  const events = []
  fields.cash.addEventListener("input", (e) => events.push(e))

  computeModule.setComputeReducer("split", ({ allowance, total }) => ({ cash: total - allowance }))
  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: ["cash"], fields }),
  )

  controller.recompute({ target: fields.allowance })
  expect(fields.cash.value).toBe("400")
  // Real browsers do NOT fire input on a programmatic .value write (issue #76) —
  // the controller must dispatch a real bubbling Event("input") itself.
  expect(events.length).toBe(1)
  expect(events[0].type).toBe("input")
  expect(events[0].bubbles).toBe(true)
})

test("an UNCHANGED output write dispatches NO input event (the change guard)", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 400),
    total: makeField("total", 500),
  }
  let cashEvents = 0
  fields.cash.addEventListener("input", () => cashEvents++)

  // The reducer returns the value cash already holds → no write, no dispatch.
  computeModule.setComputeReducer("split", ({ allowance, total }) => ({ cash: total - allowance }))
  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: ["cash"], fields }),
  )

  controller.recompute({ target: fields.allowance })
  expect(fields.cash.value).toBe("400")
  expect(cashEvents).toBe(0)
})

test("overlapping inputs/outputs (payment_split shape) settle — no infinite recompute loop", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 0),
    leasing: makeField("leasing", 0),
    total: makeField("total", 500),
  }
  let reducerCalls = 0
  // The SHIPPED payment_split reducer shape: reads fields it also writes.
  computeModule.setComputeReducer("payment_split", ({ allowance, total }) => {
    reducerCalls++
    if (allowance >= total) return { allowance: total, cash: 0, leasing: 0 }
    return { allowance, cash: total - allowance, leasing: 0 }
  })

  const controller = buildController(
    makeRoot({
      reducer: "payment_split",
      inputs: ["allowance", "cash", "leasing", "total"],
      outputs: ["allowance", "cash", "leasing"],
      fields,
    }),
  )
  // Wire every output like the DOM would: a dispatched input re-enters recompute
  // (input->reactive#recompute bubbles to the root). Without the change guard
  // this recurses forever; with it, the second pass writes nothing and stops.
  for (const name of ["allowance", "cash", "leasing"]) {
    fields[name].addEventListener("input", (e) => controller.recompute(e))
  }

  controller.recompute({ target: fields.allowance })

  expect(fields.cash.value).toBe("400")
  expect(fields.allowance.value).toBe("100")
  expect(fields.leasing.value).toBe("0")
  // Initial run + exactly one re-entry per changed output (cash) — then settled.
  expect(reducerCalls).toBe(2)
})

test("a chained listener on an output field fires via the dispatched event (summary repaint)", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 0),
    total: makeField("total", 500),
  }
  // Simulates a summary repaint / a second compute hanging off the output field.
  let summary = null
  fields.cash.addEventListener("input", (e) => {
    summary = `cash is ${fields.cash.value}`
    expect(e.bubbles).toBe(true)
  })

  computeModule.setComputeReducer("split", ({ allowance, total }) => ({ cash: total - allowance }))
  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: ["cash"], fields }),
  )

  controller.recompute({ target: fields.allowance })
  expect(summary).toBe("cash is 400") // the chained repaint saw the new value
})
