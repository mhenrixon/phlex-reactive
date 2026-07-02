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
      // Real DOM: dispatchEvent sets event.target to the dispatching element —
      // that's what lets a re-entrant recompute see WHICH field just changed.
      // (defineProperty because Event#target is a read-only prototype getter.)
      Object.defineProperty(event, "target", { value: this, configurable: true })
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

// ---------------------------------------------------------------------------
// Issue #75: the reducer's second argument — meta = { changed } — tells a
// multi-way/mutual rebalance WHICH declared input the user just edited.
// ---------------------------------------------------------------------------

test("editing an owned declared input passes its name as meta.changed", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    total: makeField("total", 500),
  }
  let meta
  computeModule.setComputeReducer("split", (_values, m) => {
    meta = m
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: [], fields }),
  )
  controller.recompute({ target: fields.allowance })

  expect(meta).toEqual({ changed: "allowance" })
})

test("a direct recompute() call (no event) passes changed: null", () => {
  const fields = { total: makeField("total", 500) }
  let meta
  computeModule.setComputeReducer("split", (_values, m) => {
    meta = m
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["total"], outputs: [], fields }),
  )
  controller.recompute()

  expect(meta).toEqual({ changed: null })
})

test("an event from a field NOT among the declared inputs passes changed: null", () => {
  const fields = { total: makeField("total", 500) }
  const stray = makeField("note", "hello")
  stray._root = fields.total._root // ownership isn't the problem here — the name is
  let meta
  computeModule.setComputeReducer("split", (_values, m) => {
    meta = m
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["total"], outputs: [], fields }),
  )
  stray._root = controller.element
  controller.recompute({ target: stray })

  expect(meta).toEqual({ changed: null })
})

test("an event from a field owned by a NESTED reactive root passes changed: null", () => {
  const fields = { total: makeField("total", 500) }
  let meta
  computeModule.setComputeReducer("split", (_values, m) => {
    meta = m
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["total"], outputs: [], fields }),
  )
  // Same name as a declared input, but its nearest reactive root is a nested
  // one (issue #15) — the outer compute must not treat it as its own edit.
  const nested = makeField("total", 42)
  nested._root = { id: "nested-root" }
  controller.recompute({ target: nested })

  expect(meta).toEqual({ changed: null })
})

// The issue's three-way rebalance: field_a + field_b + field_c must always sum
// to total. Editing field_c makes field_a the derived field; editing anything
// else derives field_c. One reducer, branching on meta.changed. The reducer is
// CONVERGENT (see compute.js): the output write dispatches a real input event
// (#76) which re-enters recompute with changed = the output's name — that pass
// recomputes values already in the DOM, so the change guard settles the chain.
test("three-way rebalance: one reducer branches on changed; both directions settle", () => {
  const fields = {
    field_a: makeField("field_a", 100),
    field_b: makeField("field_b", 50),
    field_c: makeField("field_c", 350),
    total: makeField("total", 500),
  }
  let reducerCalls = 0
  computeModule.setComputeReducer("three_way_split", ({ field_a, field_b, field_c, total }, { changed }) => {
    reducerCalls++
    if (changed === "field_c") return { field_a: total - field_c - field_b }
    return { field_c: total - field_a - field_b }
  })

  const controller = buildController(
    makeRoot({
      reducer: "three_way_split",
      inputs: ["field_a", "field_b", "field_c", "total"],
      outputs: ["field_a", "field_c"],
      fields,
    }),
  )
  // Wire the outputs like the DOM would: the dispatched input event bubbles to
  // the root and re-enters recompute (input->reactive#recompute).
  for (const name of ["field_a", "field_b", "field_c"]) {
    fields[name].addEventListener("input", (e) => controller.recompute(e))
  }

  // Edit field_a: 100 → 200. field_c is the derived field.
  fields.field_a.value = 200
  controller.recompute({ target: fields.field_a })
  expect(fields.field_c.value).toBe("250") // 500 - 200 - 50
  expect(fields.field_a.value).toBe("200")
  // Initial pass + the re-entrant pass from field_c's dispatched input, which
  // (changed === "field_c") recomputes field_a to its current value → settled.
  expect(reducerCalls).toBe(2)
  expect(Number(fields.field_a.value) + Number(fields.field_b.value) + Number(fields.field_c.value)).toBe(500)

  // Edit field_c: 250 → 100. Now field_a is the derived field.
  reducerCalls = 0
  fields.field_c.value = 100
  controller.recompute({ target: fields.field_c })
  expect(fields.field_a.value).toBe("350") // 500 - 100 - 50
  expect(fields.field_c.value).toBe("100")
  expect(reducerCalls).toBe(2) // bounded: initial + one convergent re-entry
  expect(Number(fields.field_a.value) + Number(fields.field_b.value) + Number(fields.field_c.value)).toBe(500)
})

test("existing one-arg reducers keep working (backward compatible)", () => {
  const fields = {
    allowance: makeField("allowance", 100),
    cash: makeField("cash", 0),
    total: makeField("total", 500),
  }
  // A pre-#75 reducer: declared with ONE parameter, ignores the meta arg.
  computeModule.setComputeReducer("split", ({ allowance, total }) => ({ cash: total - allowance }))
  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: ["cash"], fields }),
  )

  controller.recompute({ target: fields.allowance })
  expect(fields.cash.value).toBe("400")
})
