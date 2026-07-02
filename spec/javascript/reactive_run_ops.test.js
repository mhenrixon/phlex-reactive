// Unit tests for runOps + the client-op interpreter (issue #95) — the
// zero-round-trip half of on_client:
//
//   * runOps NEVER fetches: no token, no params, no POST — the fetch stub in
//     this file THROWS if touched.
//   * Ops are whitelist-interpreted (CLIENT_OPS); an unknown name warns and is
//     skipped while the REST of the chain still applies (client-side
//     default-deny; a stale/newer ops attr must never break the page).
//   * Selector targets resolve WITHIN this root and exclude nested reactive
//     roots' subtrees (issue #15 semantics); "@root" is the root itself;
//     global: true escapes to document.
//   * outside:/window: mirror dispatch()'s #80 semantics — bail inside the
//     root before ANYTHING, and never preventDefault a window-bound trigger.
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

// A fake DOM node: hidden flag, classList over a Set, and `closest` returning
// the nearest reactive root (`owner`) — how the ownership guard decides.
function makeEl({ owner = null } = {}) {
  const el = {
    hidden: false,
    classes: new Set(),
    closest: () => owner,
  }
  el.classList = {
    add: (...cs) => cs.forEach((c) => el.classes.add(c)),
    remove: (...cs) => cs.forEach((c) => el.classes.delete(c)),
    toggle: (c) => (el.classes.has(c) ? el.classes.delete(c) : el.classes.add(c)),
  }
  return el
}

// A reactive root whose querySelectorAll answers from a selector -> elements
// map. `contains` consults the event target's `__inside` flag (outside guard).
function makeRoot(matches = {}) {
  return {
    isConnected: true,
    id: "tabs",
    hidden: false,
    getAttribute: () => null,
    setAttribute: () => {},
    removeAttribute: () => {},
    dispatchEvent: () => {},
    contains: (el) => el?.__inside === true,
    querySelectorAll: (sel) => matches[sel] ?? [],
  }
}

function buildController(root, { documentMatches = {} } = {}) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.fetch = () => {
    throw new Error("runOps must NEVER fetch")
  }
  globalThis.document = {
    querySelector: () => null,
    querySelectorAll: (sel) => documentMatches[sel] ?? [],
    dispatchEvent: () => {},
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return controller
}

function fire(controller, { ops, outside, windowBound, target } = {}) {
  const event = {
    params: { ops, outside, window: windowBound },
    target: target ?? { __inside: false },
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
  controller.runOps(event)
  return event
}

// --- the core ops -----------------------------------------------------------

test("show/hide/toggle flip the hidden attribute on owned matches", () => {
  const root = makeRoot()
  const a = makeEl({ owner: root })
  const b = makeEl({ owner: root })
  b.hidden = true
  root.querySelectorAll = (sel) => ({ "#a": [a], "#b": [b], ".both": [a, b] })[sel] ?? []
  const controller = buildController(root)

  fire(controller, { ops: [["hide", { to: "#a" }]] })
  expect(a.hidden).toBe(true)

  fire(controller, { ops: [["show", { to: "#b" }]] })
  expect(b.hidden).toBe(false)

  fire(controller, { ops: [["toggle", { to: ".both" }]] })
  expect(a.hidden).toBe(false)
  expect(b.hidden).toBe(true)
})

test("class ops add, remove, and toggle on every owned match", () => {
  const root = makeRoot()
  const tab = makeEl({ owner: root })
  tab.classes.add("stale")
  root.querySelectorAll = () => [tab]
  const controller = buildController(root)

  fire(controller, {
    ops: [
      ["add_class", { to: ".tab", classes: ["active", "current"] }],
      ["remove_class", { to: ".tab", classes: ["stale"] }],
      ["toggle_class", { to: ".tab", classes: ["current"] }],
    ],
  })

  expect([...tab.classes].sort()).toEqual(["active"])
})

test("ops apply in order (hide-then-show tabs pattern lands on the last state)", () => {
  const root = makeRoot()
  const panel = makeEl({ owner: root })
  root.querySelectorAll = () => [panel]
  const controller = buildController(root)

  fire(controller, { ops: [["hide", { to: ".panel" }], ["show", { to: ".panel" }]] })

  expect(panel.hidden).toBe(false)
})

// --- target resolution ------------------------------------------------------

test("a nested reactive root's elements are NOT touched (issue #15 semantics)", () => {
  const root = makeRoot()
  const nestedRoot = makeRoot()
  const mine = makeEl({ owner: root })
  const theirs = makeEl({ owner: nestedRoot })
  root.querySelectorAll = () => [mine, theirs] // querySelectorAll descends into nested roots
  const controller = buildController(root)

  fire(controller, { ops: [["hide", { to: ".panel" }]] })

  expect(mine.hidden).toBe(true)
  expect(theirs.hidden).toBe(false)
})

test("global: true escapes root scoping and skips the ownership filter", () => {
  const root = makeRoot()
  const overlay = makeEl({ owner: null }) // outside any reactive root
  const controller = buildController(root, { documentMatches: { "#overlay": [overlay] } })

  fire(controller, { ops: [["hide", { to: "#overlay", global: true }]] })

  expect(overlay.hidden).toBe(true)
})

test('"@root" targets the component root itself', () => {
  const root = makeRoot()
  const controller = buildController(root)

  fire(controller, { ops: [["toggle", { to: "@root" }]] })

  expect(root.hidden).toBe(true)
})

// --- default-deny + resilience ----------------------------------------------

test("an unknown op warns, is skipped, and the REST of the chain still applies", () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = () => [el]
  const controller = buildController(root)
  const warns = []
  const original = console.warn
  console.warn = (...args) => warns.push(args.join(" "))

  try {
    fire(controller, { ops: [["explode", { to: ".x" }], ["hide", { to: ".x" }]] })
  } finally {
    console.warn = original
  }

  expect(warns.length).toBe(1)
  expect(warns[0]).toContain("explode")
  expect(el.hidden).toBe(true)
})

test("inherited Object properties are not ops (constructor is unknown, not a gadget)", () => {
  const root = makeRoot()
  const controller = buildController(root)
  const warns = []
  const original = console.warn
  console.warn = (...args) => warns.push(args.join(" "))

  try {
    fire(controller, { ops: [["constructor", { to: "@root" }]] })
  } finally {
    console.warn = original
  }

  expect(warns.length).toBe(1)
})

test("malformed ops degrade to a no-op (string parses; garbage never throws)", () => {
  const root = makeRoot()
  root.hidden = false
  const controller = buildController(root)

  // A raw JSON string still works (hand-built attr / non-typecasting harness)…
  fire(controller, { ops: '[["toggle",{"to":"@root"}]]' })
  expect(root.hidden).toBe(true)

  // …and garbage does nothing rather than throwing.
  expect(() => fire(controller, { ops: "not json" })).not.toThrow()
  expect(() => fire(controller, { ops: 42 })).not.toThrow()
  expect(() => fire(controller, { ops: [["hide"]] })).not.toThrow() // missing args
  expect(() => fire(controller, { ops: ["not-a-pair"] })).not.toThrow()
})

// --- outside/window semantics (mirrors dispatch(), issue #80) ----------------

test("outside: bails completely for an event INSIDE the root (no ops, no preventDefault)", () => {
  const root = makeRoot()
  root.hidden = false
  const controller = buildController(root)

  const event = fire(controller, {
    ops: [["hide", { to: "@root" }]],
    outside: true,
    windowBound: true,
    target: { __inside: true },
  })

  expect(root.hidden).toBe(false)
  expect(event.defaultPrevented).toBe(false)
})

test("outside: applies for an event OUTSIDE the root, and window-bound never preventDefaults", () => {
  const root = makeRoot()
  const controller = buildController(root)

  const event = fire(controller, {
    ops: [["hide", { to: "@root" }]],
    outside: true,
    windowBound: true,
    target: { __inside: false },
  })

  expect(root.hidden).toBe(true)
  expect(event.defaultPrevented).toBe(false) // a mounted dropdown must not kill page clicks
})

test("an element-bound trigger DOES preventDefault (bare button in a form must not submit)", () => {
  const root = makeRoot()
  const controller = buildController(root)

  const event = fire(controller, { ops: [["hide", { to: "@root" }]] })

  expect(event.defaultPrevented).toBe(true)
})
