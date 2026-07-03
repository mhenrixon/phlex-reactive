// Unit test for #recompute's FIRST-WINS owned-field resolution (issue #117,
// guarding issue #15 nested-root scoping).
//
// #117 hoists the per-field ownership check out of the per-name/per-keystroke
// loop: #ownershipFilter() probes ONCE for nested reactive roots. With none it
// returns a constant-true predicate (the common fast path); WITH a nested root
// it falls back to the exact #ownsField closest() check. recompute then resolves
// every declared input/output through a per-call byName memo whose predicate is
// FIRST-WINS (`break on the first owned match`).
//
// Two things need coverage that no existing test provides:
//
//   1. FIRST-WINS among DUPLICATE OWNED names (the reason last-wins is wrong).
//      Two controls share a name and are BOTH owned by this root — a radio
//      group, or the Rails hidden+checkbox pair. #ownedField/#recompute must
//      resolve the FIRST in DOM order. Every existing compute fake returns at
//      most one field per name, so a last-wins regression would pass silently.
//      This test RESOLVES two owned duplicates and asserts the FIRST is used —
//      it goes RED against a deliberately last-wins resolver (proven locally by
//      flipping the loop to last-wins: the reducer then sees the second value).
//
//   2. NESTED-ROOT scoping under the #ownershipFilter fallback. A declared name
//      also matches a field owned by a NESTED reactive root; that field must be
//      rejected (issue #15). This forces the nested fallback branch of
//      #ownershipFilter (not the fast path), so the real owns() predicate is
//      under test.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

import * as computeModule from "../../app/javascript/phlex/reactive/compute.js"

let ReactiveController

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
  globalThis.window ??= {}
})

beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

// A fake named form control. .value coerces to String on write and fires
// NOTHING (real DOM: no `input` on a programmatic write, issue #76). closest()
// answers the element's owning reactive root so #ownsField (issue #15) can scope
// it: owned by `_root` for the reactive-root selector.
function makeField(name, value, root) {
  const listeners = []
  return {
    name,
    tagName: "INPUT",
    _root: root,
    _value: String(value),
    get value() {
      return this._value
    },
    set value(v) {
      this._value = String(v)
    },
    closest(sel) {
      return sel === '[data-controller~="reactive"]' ? this._root : null
    },
    addEventListener: (type, fn) => type === "input" && listeners.push(fn),
    dispatchEvent(event) {
      Object.defineProperty(event, "target", { value: this, configurable: true })
      if (event.type === "input") listeners.slice().forEach((fn) => fn(event))
      return true
    },
  }
}

// A root whose querySelectorAll('[name="total"]') returns the supplied list in
// DOM order, and whose querySelectorAll('[data-controller~="reactive"]') returns
// `nestedRoots`. Every other query returns []. Mirrors the compute fake's
// per-name query shape, so it answers exactly the queries the #117 recompute
// resolver issues.
function makeRoot({ reducer, inputs, outputs, totalMatches, nestedRoots = [] }) {
  const attrs = {
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  return {
    id: "outer-root",
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      if (sel === '[data-controller~="reactive"]') return nestedRoots.slice()
      if (sel === '[name="total"]') return totalMatches.slice()
      return []
    },
    closest: () => null,
  }
}

test("recompute reads the FIRST of two OWNED duplicate-named fields (issue #117 first-wins)", () => {
  // Two controls named "total" BOTH owned by this root (e.g. a Rails
  // hidden+visible pair). first=500, second=42. First-wins → reducer sees 500;
  // last-wins → it would see 42 (this is what makes the test bite).
  let seenValues
  computeModule.setComputeReducer("echo_total", (values) => {
    seenValues = values
    return {}
  })

  // Build the root first so both duplicates can be owned by it.
  const first = makeField("total", 500, null)
  const second = makeField("total", 42, null)
  const root = makeRoot({
    reducer: "echo_total",
    inputs: ["total"],
    outputs: [],
    totalMatches: [first, second], // DOM order: first, then second
    nestedRoots: [], // NO nested roots here → fast path is taken
  })
  first._root = root
  second._root = root // BOTH owned by this root

  const controller = new ReactiveController()
  controller.element = root
  controller.recompute({ target: first })

  expect(seenValues).toEqual({ total: 500 }) // FIRST wins, not 42
})

test("recompute writes an output to the FIRST of two OWNED duplicate-named fields (issue #117 first-wins)", () => {
  computeModule.setComputeReducer("set_total", () => ({ total: 999 }))

  const first = makeField("total", 0, null)
  const second = makeField("total", 0, null)
  const root = makeRoot({
    reducer: "set_total",
    inputs: [],
    outputs: ["total"],
    totalMatches: [first, second],
    nestedRoots: [],
  })
  first._root = root
  second._root = root

  const controller = new ReactiveController()
  controller.element = root
  controller.recompute({ target: first })

  // The write landed on the FIRST owned field; the second is untouched.
  expect(first.value).toBe("999")
  expect(second.value).toBe("0")
})

test("recompute skips a duplicate owned by a NESTED reactive root under the ownership fallback (issues #117/#15)", () => {
  // The outer root owns `owned` (500); a NESTED reactive root owns `nested` (42),
  // and both are named "total". Because a nested reactive root is present,
  // #ownershipFilter takes the closest()-based fallback, NOT the fast path — so
  // the nested field must be rejected and the OWNED one used.
  let seenValues
  computeModule.setComputeReducer("echo_total", (values) => {
    seenValues = values
    return {}
  })

  const nestedRoot = { id: "nested-root" }
  const owned = makeField("total", 500, null)
  const nested = makeField("total", 42, nestedRoot)
  const root = makeRoot({
    reducer: "echo_total",
    inputs: ["total"],
    outputs: [],
    totalMatches: [nested, owned], // nested FIRST in DOM order — ownership must still pick `owned`
    nestedRoots: [nestedRoot], // present → nested fallback branch of #ownershipFilter
  })
  owned._root = root // owned by THIS root
  // nested._root stays nestedRoot → #ownsField(nested) === false

  const controller = new ReactiveController()
  controller.element = root
  controller.recompute({ target: owned })

  // The nested field is rejected even though it is FIRST in DOM order — ownership
  // wins over position. The reducer sees the owned 500, never the nested 42.
  expect(seenValues).toEqual({ total: 500 })
})
