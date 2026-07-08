// Unit tests for the tag-chip input (issue #203) — reactive_tags, the composed
// combobox/tags primitive.
//
// The ROOT names the hidden field that stores the COMMA-JOINED value
// (data-reactive-tags-field); the chip list ([data-reactive-tags-list]) is a
// pure CLIENT PROJECTION of that field, rebuilt on every sync by cloning the
// server-owned <template data-reactive-tags-template> chip (textContent writes
// only — never innerHTML). Enter on the query input adds the typed text
// (tagsAdd) UNLESS listnav already picked a highlighted option; clicking an
// option adds its declared tag (tagsPick); a chip's remove button drops it
// (tagsRemove). Tags dedupe case-insensitively keeping the first casing; a
// selected option is hidden + marked data-reactive-tags-selected, and
// #syncFilter keeps it hidden through re-filters. All of it is FORM state — no
// token, no POST, ever.
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

// The reactive_filter FakeNode, extended for the tags projection:
//   - appendChild/removeChild/firstChild for the chip-list rebuild
//   - cloneNode(true) + a writable textContent for template chip cloning
//   - dispatchEvent log (the hidden field's set-value + input contract)
//   - an [attr*="value"] matcher (finding the clone's remove trigger)
class FakeNode {
  constructor(opts = {}) {
    const {
      tag = "div",
      id = "",
      name = null,
      type = null,
      value = "",
      text = "",
      controller = null,
      attrs = {},
    } = opts
    this.tag = tag.toLowerCase()
    this.id = id
    this.name = name
    this.type = type
    this.value = value
    this.text = text
    this.hidden = false
    this.parentNode = null
    this.children = []
    this.attrs = { ...attrs }
    this.isConnected = true
    this.listeners = {}
    this.dispatched = []
    if (controller) this.attrs["data-controller"] = controller
  }

  append(...nodes) {
    for (const n of nodes) {
      n.parentNode = this
      this.children.push(n)
    }
    return this
  }

  appendChild(node) {
    this.append(node)
    return node
  }

  removeChild(node) {
    this.children = this.children.filter((c) => c !== node)
    node.parentNode = null
    return node
  }

  get firstChild() {
    return this.children[0] ?? null
  }

  cloneNode(deep) {
    const copy = new FakeNode({
      tag: this.tag,
      id: this.id,
      name: this.name,
      type: this.type,
      value: this.value,
      text: this.text,
      attrs: { ...this.attrs },
    })
    copy.hidden = this.hidden
    if (deep) for (const child of this.children) copy.append(child.cloneNode(true))
    return copy
  }

  get textContent() {
    return this.text + this.children.map((c) => c.textContent).join("")
  }

  set textContent(value) {
    this.text = String(value)
    this.children = []
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
    const attrContains = selector.match(/^\[([\w-]+)\*="(.*)"\]$/)
    if (attrContains) return (this.getAttribute(attrContains[1]) ?? "").includes(attrContains[2])
    const byId = selector.match(/^#([\w-]+)$/)
    if (byId) return this.id === byId[1]
    const named = selector.match(/^\[name="(.*)"\]$/)
    if (named) return this.name === named[1]
    const attrEq = selector.match(/^\[([\w-]+)=(?:"([^"]*)"|([^\]"]+))\]$/)
    if (attrEq) return this.getAttribute(attrEq[1]) === (attrEq[2] ?? attrEq[3])
    const attrPresent = selector.match(/^\[([\w-]+)\]$/)
    if (attrPresent) return this.getAttribute(attrPresent[1]) !== null
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
  dispatchEvent(event) {
    this.dispatched.push(event)
  }
  emit(name, event = {}) {
    for (const fn of this.listeners[name] ?? []) fn({ type: name, ...event })
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

// The template chip prototype: <span class=chip><span data-reactive-tag-text>
// </span><button data-action=…tagsRemove></button></span>. Lives in
// template.content (inert — NOT in the root's query tree), like a real
// <template>.
function chipTemplate() {
  const proto = new FakeNode({ tag: "span", attrs: { class: "chip" } })
  proto.append(
    new FakeNode({ tag: "span", attrs: { "data-reactive-tag-text": "" } }),
    new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#tagsRemove" } }),
  )
  const template = new FakeNode({ tag: "template", attrs: { "data-reactive-tags-template": "" } })
  template.content = { firstElementChild: proto }
  return template
}

function tagsOption(tag) {
  return new FakeNode({
    tag: "button",
    attrs: {
      role: "option",
      "data-action": "click->reactive#tagsPick",
      "data-reactive-tag-param": tag,
      "data-reactive-filter-text": tag.toLowerCase(),
    },
  })
}

// A full tags widget: hidden value field, chip list + template, a query input
// carrying the listnav option param, and preloaded options. filter: true adds
// the reactive_filter binding driven by the same query input.
function tagsWidget({ value = "", filter = false, options = [], template = chipTemplate() } = {}) {
  const attrs = { "data-reactive-tags-field": '[name="tags"]' }
  if (filter) {
    attrs["data-reactive-filter-input"] = '[name="tag_query"]'
    attrs["data-reactive-filter-option"] = "[role=option]"
  }
  const root = new FakeNode({ tag: "div", id: "tags-root", controller: "reactive", attrs })
  const field = new FakeNode({ tag: "input", type: "hidden", name: "tags", value })
  const list = new FakeNode({ tag: "div", attrs: { "data-reactive-tags-list": "" } })
  const query = new FakeNode({
    tag: "input",
    name: "tag_query",
    attrs: { "data-reactive-listnav-option-param": "[role=option]" },
  })
  root.append(field, list, query)
  if (template) root.append(template)
  for (const option of options) root.append(option)
  return { root, field, list, query }
}

function keyEvent(target, overrides = {}) {
  return {
    currentTarget: target,
    target,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
    ...overrides,
  }
}

function chipTexts(list) {
  return list.children.map((chip) => chip.textContent)
}

// --- connect seeding ---------------------------------------------------------

test("connect() projects the hidden value into chips (template clone + textContent)", () => {
  const { root, list } = tagsWidget({ value: "Ruby,Rails" })
  buildController(root).connect()

  expect(chipTexts(list)).toEqual(["Ruby", "Rails"])
  // Each chip is stamped with its tag and its remove trigger carries the param.
  const chip = list.children[0]
  expect(chip.getAttribute("data-reactive-tag")).toBe("Ruby")
  const remove = chip.querySelectorAll('[data-action*="reactive#tagsRemove"]')[0]
  expect(remove.getAttribute("data-reactive-tag-param")).toBe("Ruby")
})

test("connect() normalizes ragged server values (trim, drop blanks, dedupe case-insensitively)", () => {
  const { root, list } = tagsWidget({ value: " Ruby , ,rails,RUBY," })
  buildController(root).connect()

  expect(chipTexts(list)).toEqual(["Ruby", "rails"])
})

test("connect() with an empty value renders no chips", () => {
  const { root, list } = tagsWidget({ value: "" })
  buildController(root).connect()

  expect(list.children).toEqual([])
})

test("connect() hides + marks options whose tag is already selected", () => {
  const ruby = tagsOption("Ruby")
  const rails = tagsOption("Rails")
  const { root } = tagsWidget({ value: "ruby", options: [ruby, rails] })
  buildController(root).connect()

  expect(ruby.hidden).toBe(true)
  expect(ruby.hasAttribute("data-reactive-tags-selected")).toBe(true)
  expect(rails.hidden).toBe(false)
  expect(rails.hasAttribute("data-reactive-tags-selected")).toBe(false)
})

// --- tagsAdd (Enter on the query input) ---------------------------------------

test("tagsAdd adds the typed text: value, chip, cleared input, preventDefault", () => {
  const { root, field, list, query } = tagsWidget({ value: "Ruby" })
  const controller = buildController(root)
  controller.connect()

  query.value = "Rails"
  const event = keyEvent(query)
  controller.tagsAdd(event)

  expect(field.value).toBe("Ruby,Rails")
  expect(chipTexts(list)).toEqual(["Ruby", "Rails"])
  expect(query.value).toBe("")
  expect(event.defaultPrevented).toBe(true)
})

test("tagsAdd splits a comma-separated paste into individual tags", () => {
  const { root, field } = tagsWidget()
  const controller = buildController(root)
  controller.connect()

  const { query } = { query: root.querySelectorAll('[name="tag_query"]')[0] }
  query.value = "a, b ,c"
  controller.tagsAdd(keyEvent(query))

  expect(field.value).toBe("a,b,c")
})

test("tagsAdd on blank input adds nothing but still preventDefaults (no form submit)", () => {
  const { root, field, query } = tagsWidget({ value: "Ruby" })
  const controller = buildController(root)
  controller.connect()

  query.value = "   "
  const event = keyEvent(query)
  controller.tagsAdd(event)

  expect(field.value).toBe("Ruby")
  expect(event.defaultPrevented).toBe(true)
})

test("tagsAdd dedupes case-insensitively and keeps the typed text for correction", () => {
  const { root, field, query } = tagsWidget({ value: "Ruby" })
  const controller = buildController(root)
  controller.connect()

  query.value = "RUBY"
  controller.tagsAdd(keyEvent(query))

  expect(field.value).toBe("Ruby")
  expect(query.value).toBe("RUBY")
})

test("tagsAdd is a no-op when listnavPick already handled the Enter (defaultPrevented)", () => {
  const { root, field, query } = tagsWidget()
  const controller = buildController(root)
  controller.connect()

  query.value = "typed"
  controller.tagsAdd(keyEvent(query, { defaultPrevented: true }))

  expect(field.value).toBe("")
})

test("tagsAdd defers to a visible highlighted option (order-independent double-add guard)", () => {
  const ruby = tagsOption("Ruby")
  ruby.setAttribute("data-reactive-highlighted", "true")
  const { root, field, query } = tagsWidget({ options: [ruby] })
  const controller = buildController(root)
  controller.connect()

  query.value = "typed"
  const event = keyEvent(query)
  controller.tagsAdd(event)

  expect(field.value).toBe("")
  expect(event.defaultPrevented).toBe(false) // listnavPick's Enter, not ours
})

// --- tagsPick (click / listnav Enter on an option) -----------------------------

test("tagsPick adds the option's declared tag and hides + marks the option", () => {
  const ruby = tagsOption("Ruby")
  const { root, field, list } = tagsWidget({ options: [ruby] })
  const controller = buildController(root)
  controller.connect()

  controller.tagsPick(keyEvent(ruby))

  expect(field.value).toBe("Ruby")
  expect(chipTexts(list)).toEqual(["Ruby"])
  expect(ruby.hidden).toBe(true)
  expect(ruby.hasAttribute("data-reactive-tags-selected")).toBe(true)
})

test("tagsPick clears the filter query so the next tag starts from the full list", () => {
  const ruby = tagsOption("Ruby")
  const rails = tagsOption("Rails")
  const { root, query } = tagsWidget({ filter: true, options: [ruby, rails] })
  const controller = buildController(root)
  controller.connect()

  query.value = "ru"
  query.emit("input", { target: query }) // narrow to Ruby
  root.emit("input", { target: query })
  expect(rails.hidden).toBe(true)

  controller.tagsPick(keyEvent(ruby))

  expect(query.value).toBe("")
  expect(ruby.hidden).toBe(true) // selected stays hidden
  expect(rails.hidden).toBe(false) // re-filtered against the cleared query
})

// --- tagsRemove (a chip's remove button) --------------------------------------

test("tagsRemove drops the tag, rebuilds the chips, and resurfaces the option", () => {
  const ruby = tagsOption("Ruby")
  const { root, field, list } = tagsWidget({ value: "Ruby,Rails", options: [ruby] })
  const controller = buildController(root)
  controller.connect()
  expect(ruby.hidden).toBe(true)

  const remove = list.children[0].querySelectorAll('[data-action*="reactive#tagsRemove"]')[0]
  controller.tagsRemove(keyEvent(remove))

  expect(field.value).toBe("Rails")
  expect(chipTexts(list)).toEqual(["Rails"])
  expect(ruby.hidden).toBe(false)
  expect(ruby.hasAttribute("data-reactive-tags-selected")).toBe(false)
})

test("tagsRemove of an absent tag is a no-op", () => {
  const { root, field } = tagsWidget({ value: "Ruby" })
  const controller = buildController(root)
  controller.connect()

  const stray = new FakeNode({ tag: "button", attrs: { "data-reactive-tag-param": "Ghost" } })
  controller.tagsRemove(keyEvent(stray))

  expect(field.value).toBe("Ruby")
})

// --- filter interplay ----------------------------------------------------------

test("#syncFilter keeps a selected option hidden even when the query clears", () => {
  const ruby = tagsOption("Ruby")
  const rails = tagsOption("Rails")
  const { root, query } = tagsWidget({ value: "Ruby", filter: true, options: [ruby, rails] })
  buildController(root).connect()
  expect(ruby.hidden).toBe(true)

  // A cleared query re-filters everything visible — except the selected tag.
  query.value = ""
  root.emit("input", { target: query })

  expect(ruby.hidden).toBe(true)
  expect(rails.hidden).toBe(false)
})

// --- value write contract -------------------------------------------------------

test("a tags write dispatches input on the hidden field (dirty/show/compute contract)", () => {
  const { root, field, query } = tagsWidget()
  const controller = buildController(root)
  controller.connect()

  query.value = "Ruby"
  controller.tagsAdd(keyEvent(query))

  expect(field.dispatched.length).toBe(1)
  expect(field.dispatched[0].type).toBe("input")
})

// --- morph re-seed ---------------------------------------------------------------

test("turbo:morph-element re-projects the chips from the (new) server value", () => {
  const { root, field, list } = tagsWidget({ value: "Ruby" })
  buildController(root).connect()
  expect(chipTexts(list)).toEqual(["Ruby"])

  field.value = "Elixir,Go" // the morph wrote server truth
  root.emit("turbo:morph-element")

  expect(chipTexts(list)).toEqual(["Elixir", "Go"])
})

// --- degraded bindings ------------------------------------------------------------

test("a missing chip template warns once; the hidden value still updates", () => {
  const { root, field, query } = tagsWidget({ template: null })
  const controller = buildController(root)
  const warnings = []
  const originalWarn = console.warn
  console.warn = (message) => warnings.push(String(message))
  try {
    controller.connect()
    query.value = "Ruby"
    controller.tagsAdd(keyEvent(query))
    query.value = "Rails"
    controller.tagsAdd(keyEvent(query))
  } finally {
    console.warn = originalWarn
  }

  expect(field.value).toBe("Ruby,Rails")
  const templateWarnings = warnings.filter((message) => message.includes("data-reactive-tags-template"))
  expect(templateWarnings.length).toBe(1)
})

test("a root without the tags binding ignores the tags actions (default-deny)", () => {
  const root = new FakeNode({ tag: "div", id: "plain-root", controller: "reactive" })
  const input = new FakeNode({ tag: "input", name: "q", value: "typed" })
  root.append(input)
  const controller = buildController(root)
  controller.connect()

  const event = keyEvent(input)
  controller.tagsAdd(event)

  expect(event.defaultPrevented).toBe(false)
  expect(input.value).toBe("typed")
})
