// Unit tests for value-conditional visibility (issue #161) — reactive_show,
// the x-show / data-show equivalent, entirely client-side.
//
// The TARGET element declares which owned field controls it
// (data-reactive-show-field) plus ONE literal predicate
// (data-reactive-show-equals / -not / -in). connect() gates on the presence of
// an OWNED binding (a root without one pays only the probe), installs ONE
// delegated input/change listener on the root, seeds the initial state, and
// re-syncs after a turbo:morph-element (a morph keeps the controller connected
// and fires no Stimulus lifecycle — the dirty-tracking precedent). Each sync
// reads the field's CURRENT value — checkbox → checked as "true"/"false",
// radio group → the checked radio's value, else .value — evaluates the literal
// predicate, and toggles the `hidden` property. No round trip, no token; a
// missing field or malformed predicate leaves visibility alone (default-deny:
// a bad binding must never break the page).
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

// A minimal element stub faithful enough for the show-binding sync:
//   - type/value/checked for field reads, `hidden` for the visibility toggle
//   - data-controller for the reactive-root ownership predicate
//   - [data-reactive-show-field] and [name="X"] selector support
//   - attrs-backed get/set/removeAttribute + a listener log with emit()
class FakeNode {
  constructor(opts = {}) {
    const {
      tag = "div",
      name = null,
      type = null,
      value = "",
      checked = false,
      controller = null,
      attrs = {},
    } = opts
    this.tag = tag.toLowerCase()
    this.name = name
    this.type = type
    this.value = value
    this.checked = checked
    this.hidden = false
    this.parentNode = null
    this.children = []
    this.attrs = { ...attrs }
    this.isConnected = true
    this.listeners = {}
    if (controller) this.attrs["data-controller"] = controller
  }

  append(...nodes) {
    for (const n of nodes) {
      n.parentNode = this
      this.children.push(n)
    }
    return this
  }

  #descendants() {
    const out = []
    for (const child of this.children) out.push(child, ...child.#descendants())
    return out
  }

  matches(selector) {
    if (selector === '[data-controller~="reactive"]') {
      const c = this.attrs["data-controller"]
      return !!c && c.split(/\s+/).includes("reactive")
    }
    if (selector === "[data-reactive-show-field]") {
      return "data-reactive-show-field" in this.attrs
    }
    // The dirty-tracking opt-in probe connect() also runs.
    if (selector === '[data-action*="reactive#trackDirty"]') {
      return (this.attrs["data-action"] ?? "").includes("reactive#trackDirty")
    }
    const named = selector.match(/^\[name="(.*)"\]$/)
    if (named) return this.name === named[1]
    return false
  }

  closest(selector) {
    let node = this
    while (node) {
      if (node.matches(selector)) return node
      node = node.parentNode
    }
    return null
  }

  querySelectorAll(selector) {
    return this.#descendants().filter((n) => n.matches(selector))
  }

  getAttribute(name) {
    if (name === "name") return this.name
    return this.attrs[name] ?? null
  }
  setAttribute(name, value) {
    this.attrs[name] = String(value)
  }
  removeAttribute(name) {
    delete this.attrs[name]
  }
  hasAttribute(name) {
    return name in this.attrs
  }
  addEventListener(name, fn) {
    ;(this.listeners[name] ??= []).push(fn)
  }
  removeEventListener(name, fn) {
    this.listeners[name] = (this.listeners[name] ?? []).filter((f) => f !== fn)
  }
  emit(name, event = {}) {
    for (const fn of this.listeners[name] ?? []) fn(event)
  }
}

function buildController(rootEl) {
  const controller = new ReactiveController()
  controller.element = rootEl
  controller.tokenValue = "tok"
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  globalThis.window = { addEventListener: () => {}, removeEventListener: () => {} }
  return controller
}

function reactiveRoot(extra = {}) {
  const root = new FakeNode({ tag: "div", controller: "reactive", ...extra })
  root.id = "show-root"
  return root
}

// A show-binding target: data-reactive-show-field=<field> plus one predicate
// attr (e.g. { "data-reactive-show-not": "off" }).
function binding(field, predicateAttrs = {}) {
  return new FakeNode({ tag: "div", attrs: { "data-reactive-show-field": field, ...predicateAttrs } })
}

test("connect() seeds initial visibility from the field's current value", () => {
  const root = reactiveRoot()
  const mode = new FakeNode({ tag: "select", name: "mode", value: "off" })
  const details = binding("mode", { "data-reactive-show-not": "off" })
  root.append(mode, details)

  buildController(root).connect()

  // mode == "off" → the not:"off" predicate fails → hidden.
  expect(details.hidden).toBe(true)
})

test("an input event re-evaluates: not: shows when the value moves off the literal", () => {
  const root = reactiveRoot()
  const mode = new FakeNode({ tag: "select", name: "mode", value: "off" })
  const details = binding("mode", { "data-reactive-show-not": "off" })
  root.append(mode, details)

  buildController(root).connect()
  expect(details.hidden).toBe(true)

  mode.value = "express"
  root.emit("input", { target: mode })
  expect(details.hidden).toBe(false)

  // …and back to the literal → hidden again.
  mode.value = "off"
  root.emit("input", { target: mode })
  expect(details.hidden).toBe(true)
})

test("equals: matches the field's exact value", () => {
  const root = reactiveRoot()
  const kind = new FakeNode({ tag: "select", name: "kind", value: "basic" })
  const panel = binding("kind", { "data-reactive-show-equals": "premium" })
  panel.hidden = true // server rendered the initial state
  root.append(kind, panel)

  buildController(root).connect()
  expect(panel.hidden).toBe(true)

  kind.value = "premium"
  root.emit("change", { target: kind })
  expect(panel.hidden).toBe(false)
})

test("a checkbox compares its checked state as \"true\"/\"false\"", () => {
  const root = reactiveRoot()
  const gift = new FakeNode({ tag: "input", type: "checkbox", name: "gift", value: "on", checked: false })
  const note = binding("gift", { "data-reactive-show-equals": "true" })
  root.append(gift, note)

  buildController(root).connect()
  expect(note.hidden).toBe(true)

  gift.checked = true
  root.emit("change", { target: gift })
  expect(note.hidden).toBe(false)
})

test("Rails hidden+checkbox pair: the checkbox wins over the hidden input sharing its name", () => {
  const root = reactiveRoot()
  // Rails renders <input type=hidden name=gift value="0"> BEFORE the checkbox.
  const hiddenPair = new FakeNode({ tag: "input", type: "hidden", name: "gift", value: "0" })
  const gift = new FakeNode({ tag: "input", type: "checkbox", name: "gift", value: "1", checked: true })
  const note = binding("gift", { "data-reactive-show-equals": "true" })
  note.hidden = true
  root.append(hiddenPair, gift, note)

  buildController(root).connect()
  // The checkbox's checked state decides — not the hidden input's "0".
  expect(note.hidden).toBe(false)
})

test("a radio group reads the CHECKED radio's value; none checked reads \"\"", () => {
  const root = reactiveRoot()
  const pickup = new FakeNode({ tag: "input", type: "radio", name: "delivery", value: "pickup", checked: false })
  const ship = new FakeNode({ tag: "input", type: "radio", name: "delivery", value: "ship", checked: false })
  const address = binding("delivery", { "data-reactive-show-equals": "ship" })
  root.append(pickup, ship, address)

  const controller = buildController(root)
  controller.connect()
  expect(address.hidden).toBe(true) // none checked → "" ≠ "ship"

  ship.checked = true
  root.emit("change", { target: ship })
  expect(address.hidden).toBe(false)

  ship.checked = false
  pickup.checked = true
  root.emit("change", { target: pickup })
  expect(address.hidden).toBe(true)
})

test("in: matches any value in the declared list", () => {
  const root = reactiveRoot()
  const size = new FakeNode({ tag: "select", name: "size", value: "s" })
  const surcharge = binding("size", { "data-reactive-show-in": '["l","xl"]' })
  root.append(size, surcharge)

  buildController(root).connect()
  expect(surcharge.hidden).toBe(true)

  size.value = "xl"
  root.emit("input", { target: size })
  expect(surcharge.hidden).toBe(false)

  size.value = "m"
  root.emit("input", { target: size })
  expect(surcharge.hidden).toBe(true)
})

test("a missing field leaves visibility untouched (no crash, no flip)", () => {
  const root = reactiveRoot()
  const shown = binding("ghost", { "data-reactive-show-equals": "x" })
  const hiddenOne = binding("ghost", { "data-reactive-show-equals": "x" })
  hiddenOne.hidden = true
  root.append(shown, hiddenOne)

  buildController(root).connect()

  // No owned field named "ghost" → both keep their server-rendered state.
  expect(shown.hidden).toBe(false)
  expect(hiddenOne.hidden).toBe(true)
})

test("a malformed in: list is skipped (warn, never a throw, visibility untouched)", () => {
  const root = reactiveRoot()
  const size = new FakeNode({ tag: "select", name: "size", value: "l" })
  const bad = binding("size", { "data-reactive-show-in": "not-json" })
  bad.hidden = true
  root.append(size, bad)

  expect(() => buildController(root).connect()).not.toThrow()
  expect(bad.hidden).toBe(true)
})

test("a binding with NO predicate attr is skipped (default-deny, visibility untouched)", () => {
  const root = reactiveRoot()
  const size = new FakeNode({ tag: "select", name: "size", value: "l" })
  const bare = binding("size")
  bare.hidden = true
  root.append(size, bare)

  expect(() => buildController(root).connect()).not.toThrow()
  expect(bare.hidden).toBe(true)
})

test("nested reactive root: the outer controller neither evaluates the inner root's bindings nor reads its fields", () => {
  const outer = reactiveRoot()
  const outerMode = new FakeNode({ tag: "select", name: "mode", value: "on" })
  const outerPanel = binding("mode", { "data-reactive-show-not": "off" })
  outerPanel.hidden = true

  const inner = new FakeNode({ tag: "div", controller: "reactive" })
  const innerMode = new FakeNode({ tag: "select", name: "inner_mode", value: "off" })
  const innerPanel = binding("inner_mode", { "data-reactive-show-not": "off" })
  inner.append(innerMode, innerPanel)

  // The outer root also carries a binding on a field that lives ONLY inside the
  // inner root — the outer controller must not read across the boundary.
  const crossPanel = binding("inner_mode", { "data-reactive-show-not": "off" })
  crossPanel.hidden = true

  outer.append(outerMode, outerPanel, inner, crossPanel)
  buildController(outer).connect()

  expect(outerPanel.hidden).toBe(false) // outer's own binding evaluated ("on" ≠ "off")
  expect(innerPanel.hidden).toBe(false) // untouched by the outer sync (inner would hide it)
  expect(crossPanel.hidden).toBe(true) // inner field is invisible to the outer read
})

test("connect() installs NO listeners for a root without show bindings (the gate)", () => {
  const root = reactiveRoot()
  root.append(new FakeNode({ tag: "select", name: "mode", value: "off" }))

  buildController(root).connect()

  expect(root.listeners.input ?? []).toHaveLength(0)
  expect(root.listeners.change ?? []).toHaveLength(0)
})

test("a turbo:morph-element re-syncs against the (Turbo-preserved) field value", () => {
  const root = reactiveRoot()
  const mode = new FakeNode({ tag: "select", name: "mode", value: "express" })
  const details = binding("mode", { "data-reactive-show-not": "off" })
  root.append(mode, details)

  buildController(root).connect()
  expect(details.hidden).toBe(false)

  // A broadcast morph re-rendered the panel hidden (server truth at that
  // moment) while Turbo preserved the user's field value — the post-morph
  // re-sync reconciles from the CURRENT field value.
  details.hidden = true
  root.emit("turbo:morph-element", { target: root })
  expect(details.hidden).toBe(false)
})

test("disconnect() removes the show-sync listeners", () => {
  const root = reactiveRoot()
  const mode = new FakeNode({ tag: "select", name: "mode", value: "off" })
  const details = binding("mode", { "data-reactive-show-not": "off" })
  root.append(mode, details)

  const controller = buildController(root)
  controller.connect()
  controller.disconnect()

  expect(root.listeners.input ?? []).toHaveLength(0)
  expect(root.listeners.change ?? []).toHaveLength(0)
  expect(root.listeners["turbo:morph-element"] ?? []).toHaveLength(0)

  // A stray event after teardown must not re-evaluate.
  mode.value = "express"
  root.emit("input", { target: mode })
  expect(details.hidden).toBe(true)
})

test("two bindings on the SAME field both sync from one memoized read", () => {
  const root = reactiveRoot()
  const kind = new FakeNode({ tag: "select", name: "kind", value: "premium" })
  const panelA = binding("kind", { "data-reactive-show-equals": "premium" })
  const panelB = binding("kind", { "data-reactive-show-not": "premium" })
  panelA.hidden = true
  root.append(kind, panelA, panelB)

  buildController(root).connect()

  expect(panelA.hidden).toBe(false) // equals matches
  expect(panelB.hidden).toBe(true) // not: fails
})
