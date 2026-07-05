// Unit tests for CROSS-ROOT value-conditional visibility (issue #164) —
// reactive_show_targets, the visibility parallel to the #159 text mirror.
//
// The component that OWNS the field declares which outside, id-allowlisted
// elements it governs: the root carries data-reactive-show-targets, a JSON map
// of { field: { "#id": { equals/not/in }, … } }. The SAME show-sync pass that
// evaluates owned element bindings (issue #161) walks the declared map: it
// reads the OWNED field's current value (never a nested root's — #15), guards
// each selector id-only (warn-and-skip — the client half of the two-sided
// default-deny; the Ruby helper raises at declare time), resolves it
// DOCUMENT-WIDE, and toggles `hidden`. A target id not on the page is silently
// skipped (an unrendered tab pane is normal); malformed wire never throws.
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

// The same minimal element stub as reactive_show.test.js (field reads, hidden,
// ownership selectors, attrs + listener log).
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

// `outside` maps id selectors ("#badge") to nodes living OUTSIDE the root —
// the targets pass resolves them through document.querySelectorAll.
function buildController(rootEl, outside = {}) {
  const controller = new ReactiveController()
  controller.element = rootEl
  controller.tokenValue = "tok"
  globalThis.document = {
    querySelector: () => null,
    querySelectorAll: (sel) => (sel in outside ? [outside[sel]] : []),
    dispatchEvent: () => {},
  }
  globalThis.window = { addEventListener: () => {}, removeEventListener: () => {} }
  return controller
}

function reactiveRoot(targets = null) {
  const root = new FakeNode({ tag: "div", controller: "reactive" })
  root.id = "targets-root"
  if (targets) root.setAttribute("data-reactive-show-targets", JSON.stringify(targets))
  return root
}

test("connect() seeds an OUTSIDE target from the owned field's value (gate: targets attr alone)", () => {
  const root = reactiveRoot({ mode: { "#badge": { not: "off" } } })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "off" })
  root.append(mode) // NO owned element bindings — the targets attr alone must enable the sync
  const badge = new FakeNode({ tag: "span" })

  buildController(root, { "#badge": badge }).connect()

  expect(badge.hidden).toBe(true) // "off" fails not:"off"
  expect((root.listeners.input ?? []).length).toBe(1) // listener installed by the targets gate
})

test("an input event re-evaluates the outside target both ways", () => {
  const root = reactiveRoot({ mode: { "#badge": { not: "off" } } })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "off" })
  root.append(mode)
  const badge = new FakeNode({ tag: "span" })
  badge.hidden = true

  buildController(root, { "#badge": badge }).connect()
  expect(badge.hidden).toBe(true)

  mode.value = "express"
  root.emit("input", { target: mode })
  expect(badge.hidden).toBe(false)

  mode.value = "off"
  root.emit("input", { target: mode })
  expect(badge.hidden).toBe(true)
})

test("equals and in predicates work in the declared map", () => {
  const root = reactiveRoot({
    kind: { "#premium-tab": { equals: "premium" } },
    size: { "#surcharge": { in: ["l", "xl"] } },
  })
  const kind = new FakeNode({ tag: "select", name: "kind", value: "premium" })
  const size = new FakeNode({ tag: "select", name: "size", value: "m" })
  root.append(kind, size)
  const premiumTab = new FakeNode({ tag: "li" })
  premiumTab.hidden = true
  const surcharge = new FakeNode({ tag: "aside" })

  const controller = buildController(root, { "#premium-tab": premiumTab, "#surcharge": surcharge })
  controller.connect()

  expect(premiumTab.hidden).toBe(false) // equals matched
  expect(surcharge.hidden).toBe(true) // "m" not in [l, xl]

  size.value = "xl"
  root.emit("change", { target: size })
  expect(surcharge.hidden).toBe(false)
})

test("a checkbox-driven target compares the checked state", () => {
  const root = reactiveRoot({ gift: { "#gift-banner": { equals: "true" } } })
  const gift = new FakeNode({ tag: "input", type: "checkbox", name: "gift", value: "on", checked: false })
  root.append(gift)
  const banner = new FakeNode({ tag: "div" })

  buildController(root, { "#gift-banner": banner }).connect()
  expect(banner.hidden).toBe(true)

  gift.checked = true
  root.emit("change", { target: gift })
  expect(banner.hidden).toBe(false)
})

test("a non-id selector is refused (warn + skip) while its siblings still apply", () => {
  // A hand-built wire attr must not widen the escape to class/compound
  // selectors — the client half of the two-sided default-deny.
  const root = reactiveRoot({
    mode: {
      ".panel": { not: "off" }, // refused
      "#ok": { not: "off" }, // still applies
    },
  })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "on" })
  root.append(mode)
  const sneaky = new FakeNode({ tag: "div" })
  sneaky.hidden = true
  const ok = new FakeNode({ tag: "div" })
  ok.hidden = true

  buildController(root, { ".panel": sneaky, "#ok": ok }).connect()

  expect(sneaky.hidden).toBe(true) // refused selector never toggled
  expect(ok.hidden).toBe(false) // the id sibling did
})

test("a target id not on the page is silently skipped (unrendered tab pane)", () => {
  const root = reactiveRoot({ mode: { "#gone": { not: "off" } } })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "on" })
  root.append(mode)

  expect(() => buildController(root, {}).connect()).not.toThrow()
})

test("a field owned only by a NESTED root is not read (targets untouched)", () => {
  const root = reactiveRoot({ inner_mode: { "#badge": { not: "off" } } })
  const inner = new FakeNode({ tag: "div", controller: "reactive" })
  inner.append(new FakeNode({ tag: "select", name: "inner_mode", value: "on" }))
  root.append(inner)
  const badge = new FakeNode({ tag: "span" })
  badge.hidden = true

  buildController(root, { "#badge": badge }).connect()

  expect(badge.hidden).toBe(true) // the outer root owns no inner_mode → no toggle
})

test("malformed wire JSON never throws, toggles nothing, and WARNS (the two-call mix collision symptom)", () => {
  // Two reactive_show_targets calls on one root space-join their JSON via
  // Phlex mix into exactly this kind of unparseable attr — the client must
  // surface it (warn naming the one-call fix), never silently drop both maps.
  const root = reactiveRoot()
  root.setAttribute("data-reactive-show-targets", '{"mode":{"#a":{"not":"off"}}} {"kind":{"#b":{"equals":"x"}}}')
  const mode = new FakeNode({ tag: "select", name: "mode", value: "on" })
  root.append(mode)
  const badge = new FakeNode({ tag: "span" })
  badge.hidden = true

  const warns = []
  const originalWarn = console.warn
  console.warn = (msg) => warns.push(String(msg))
  try {
    expect(() => buildController(root, { "#badge": badge }).connect()).not.toThrow()
  } finally {
    console.warn = originalWarn
  }

  expect(badge.hidden).toBe(true)
  expect(warns.some((w) => w.includes("data-reactive-show-targets") && w.includes("ONE call"))).toBe(true)
})

test("a malformed predicate in the map is skipped (empty / unknown keys)", () => {
  const root = reactiveRoot({
    mode: {
      "#a": {}, // no predicate
      "#b": { bogus: "x" }, // unknown key
      "#c": { in: "not-a-list" }, // in: must be an array
    },
  })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "on" })
  root.append(mode)
  const a = new FakeNode({ tag: "div" })
  const b = new FakeNode({ tag: "div" })
  const c = new FakeNode({ tag: "div" })
  a.hidden = b.hidden = c.hidden = true

  expect(() => buildController(root, { "#a": a, "#b": b, "#c": c }).connect()).not.toThrow()
  expect(a.hidden).toBe(true)
  expect(b.hidden).toBe(true)
  expect(c.hidden).toBe(true)
})

test("an owned element binding AND a declared target share one pass (both apply)", () => {
  const root = reactiveRoot({ mode: { "#badge": { not: "off" } } })
  const mode = new FakeNode({ tag: "select", name: "mode", value: "express" })
  const inside = new FakeNode({
    tag: "div",
    attrs: { "data-reactive-show-field": "mode", "data-reactive-show-not": "off" },
  })
  inside.hidden = true
  root.append(mode, inside)
  const badge = new FakeNode({ tag: "span" })
  badge.hidden = true

  buildController(root, { "#badge": badge }).connect()

  expect(inside.hidden).toBe(false) // the #161 owned binding
  expect(badge.hidden).toBe(false) // the #164 outside target, same sync pass
})
