// Unit tests for the draft nested-attribute rows primitive (issue #208) —
// reactive_nested_*, the "new parent + child rows" window.
//
// Add (nestedAdd) clones the association's server-owned
// <template data-reactive-nested-template="assoc"> row, swaps every NEW_ROW in
// the clone's name/id/for attributes for a fresh unique index, and appends it
// to the owned [data-reactive-nested-list="assoc"] container — no token, no
// POST, ever: the surrounding REAL form submit carries Rails'
// accepts_nested_attributes_for names. Remove (nestedRemove) deletes a draft
// row from the DOM; a row carrying a hidden [_destroy] input (a persisted row
// in an edit form) is marked "1" + hidden instead, so Rails destroys it on
// save.
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

// The reactive_tags FakeNode, extended for the nested-rows clone/renumber:
//   - setAttribute("name") stays coherent with the name property
//   - a "*" matcher (the renumber walks every descendant)
//   - a tag[attr$="value"] ends-with matcher (finding the [_destroy] input)
//   - focus() recording (add focuses the new row's first field)
class FakeNode {
  constructor(opts = {}) {
    const {
      tag = "div",
      id = "",
      name = null,
      type = null,
      value = "",
      controller = null,
      attrs = {},
    } = opts
    this.tag = tag.toLowerCase()
    this.id = id
    this.name = name
    this.type = type
    this.value = value
    this.hidden = false
    this.parentNode = null
    this.children = []
    this.attrs = { ...attrs }
    this.isConnected = true
    this.dispatched = []
    this.focused = 0
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

  cloneNode(deep) {
    const copy = new FakeNode({
      tag: this.tag,
      id: this.id,
      name: this.name,
      type: this.type,
      value: this.value,
      attrs: { ...this.attrs },
    })
    copy.hidden = this.hidden
    if (deep) for (const child of this.children) copy.append(child.cloneNode(true))
    return copy
  }

  #descendants() {
    const out = []
    for (const child of this.children) out.push(child, ...child.#descendants())
    return out
  }

  matches(selector) {
    if (selector === "*") return true
    if (selector === '[data-controller~="reactive"]') {
      const c = this.attrs["data-controller"]
      return !!c && c.split(/\s+/).includes("reactive")
    }
    const endsWith = selector.match(/^(\w*)\[([\w-]+)\$="(.*)"\]$/)
    if (endsWith) {
      if (endsWith[1] && this.tag !== endsWith[1]) return false
      return (this.getAttribute(endsWith[2]) ?? "").endsWith(endsWith[3])
    }
    const attrEq = selector.match(/^\[([\w-]+)=(?:"([^"]*)"|([^\]"]+))\]$/)
    if (attrEq) return this.getAttribute(attrEq[1]) === (attrEq[2] ?? attrEq[3])
    const attrPresent = selector.match(/^\[([\w-]+)\]$/)
    if (attrPresent) return this.getAttribute(attrPresent[1]) !== null
    const tagList = selector.split(",").map((s) => s.trim())
    if (tagList.every((s) => /^[a-z]+$/.test(s))) return tagList.includes(this.tag)
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

  getAttribute(attrName) {
    if (attrName === "name") return this.name
    if (attrName === "id") return this.id || null
    return this.attrs[attrName] ?? null
  }
  setAttribute(attrName, attrValue) {
    if (attrName === "name") {
      this.name = String(attrValue)
      return
    }
    if (attrName === "id") {
      this.id = String(attrValue)
      return
    }
    this.attrs[attrName] = String(attrValue)
  }
  hasAttribute(attrName) {
    return attrName in this.attrs
  }
  dispatchEvent(event) {
    this.dispatched.push(event)
  }
  focus() {
    this.focused += 1
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

// The template row prototype:
//   <div data-reactive-nested-row>
//     <label for="li_NEW_ROW_qty></label>
//     <input id="li_NEW_ROW_qty" name="order[line_items_attributes][NEW_ROW][quantity]">
//     <button data-action=…nestedRemove></button>
//   </div>
// Lives in template.content (inert — NOT in the root's query tree), like a
// real <template>.
function rowTemplate(assoc = "line_items") {
  const proto = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
  proto.append(
    new FakeNode({ tag: "label", attrs: { for: "li_NEW_ROW_qty" } }),
    new FakeNode({
      tag: "input",
      id: "li_NEW_ROW_qty",
      name: `order[${assoc}_attributes][NEW_ROW][quantity]`,
    }),
    new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#nestedRemove" } }),
  )
  const template = new FakeNode({ tag: "template", attrs: { "data-reactive-nested-template": assoc } })
  template.content = { firstElementChild: proto }
  return template
}

// A full nested-rows widget: the list container, the row template, and the
// add trigger, all inside one reactive root.
function nestedWidget({ assoc = "line_items", template = rowTemplate() } = {}) {
  const root = new FakeNode({ tag: "div", id: "form-root", controller: "reactive" })
  const list = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-list": assoc } })
  const add = new FakeNode({
    tag: "button",
    attrs: { "data-action": "click->reactive#nestedAdd", "data-reactive-association-param": assoc },
  })
  root.append(list, add)
  if (template) root.append(template)
  return { root, list, add }
}

function clickAdd(controller, add) {
  let prevented = 0
  controller.nestedAdd({ currentTarget: add, preventDefault: () => (prevented += 1) })
  return prevented
}

test("nestedAdd clones the template into the list and renumbers NEW_ROW in name/id/for", () => {
  const { root, list, add } = nestedWidget()
  const controller = buildController(root)

  const prevented = clickAdd(controller, add)

  expect(prevented).toBe(1)
  expect(list.children.length).toBe(1)
  const row = list.children[0]
  expect(row.getAttribute("data-reactive-nested-row")).toBe("")

  const input = row.querySelectorAll("input")[0]
  const label = row.querySelectorAll("label")[0]
  expect(input.name).toMatch(/^order\[line_items_attributes\]\[\d+\]\[quantity\]$/)
  expect(input.name).not.toContain("NEW_ROW")
  expect(input.id).not.toContain("NEW_ROW")
  expect(label.getAttribute("for")).toBe(input.id)
})

test("two adds mint DISTINCT indexes (a same-millisecond double add can't collide)", () => {
  const { root, list, add } = nestedWidget()
  const controller = buildController(root)

  clickAdd(controller, add)
  clickAdd(controller, add)

  expect(list.children.length).toBe(2)
  const names = list.children.map((row) => row.querySelectorAll("input")[0].name)
  expect(names[0]).not.toBe(names[1])
})

test("nestedAdd focuses the new row's first field (continue typing immediately)", () => {
  const { root, list, add } = nestedWidget()
  const controller = buildController(root)

  clickAdd(controller, add)

  expect(list.children[0].querySelectorAll("input")[0].focused).toBe(1)
})

test("nestedAdd appends to the RIGHT association when several collections share a root", () => {
  const root = new FakeNode({ tag: "div", id: "form-root", controller: "reactive" })
  const itemsList = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-list": "line_items" } })
  const feesList = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-list": "fees" } })
  const feesTemplate = (() => {
    const proto = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
    proto.append(new FakeNode({ tag: "input", name: "order[fees_attributes][NEW_ROW][amount]" }))
    const template = new FakeNode({ tag: "template", attrs: { "data-reactive-nested-template": "fees" } })
    template.content = { firstElementChild: proto }
    return template
  })()
  const addFees = new FakeNode({
    tag: "button",
    attrs: { "data-action": "click->reactive#nestedAdd", "data-reactive-association-param": "fees" },
  })
  root.append(itemsList, feesList, rowTemplate(), feesTemplate, addFees)
  const controller = buildController(root)

  controller.nestedAdd({ currentTarget: addFees, preventDefault: () => {} })

  expect(itemsList.children.length).toBe(0)
  expect(feesList.children.length).toBe(1)
  expect(feesList.children[0].querySelectorAll("input")[0].name).toMatch(/^order\[fees_attributes\]\[\d+\]\[amount\]$/)
})

test("a missing template warns once and does nothing (a half-built binding is loud, never throwing)", () => {
  const { root, list, add } = nestedWidget({ template: null })
  const controller = buildController(root)
  const warnings = []
  const originalWarn = console.warn
  console.warn = (msg) => warnings.push(msg)

  try {
    clickAdd(controller, add)
    clickAdd(controller, add)
  } finally {
    console.warn = originalWarn
  }

  expect(list.children.length).toBe(0)
  expect(warnings.length).toBe(1)
  expect(warnings[0]).toContain("nested")
})

test("a list/template inside a NESTED reactive root is not this root's (issue #15 ownership)", () => {
  const { root, add } = nestedWidget({ template: null })
  const inner = new FakeNode({ tag: "div", id: "inner-root", controller: "reactive" })
  const innerList = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-list": "line_items" } })
  inner.append(innerList, rowTemplate())
  root.append(inner)
  const controller = buildController(root)
  const originalWarn = console.warn
  console.warn = () => {}

  try {
    clickAdd(controller, add)
  } finally {
    console.warn = originalWarn
  }

  expect(innerList.children.length).toBe(0)
})

test("nestedRemove deletes a DRAFT row (no [_destroy] input) from the DOM", () => {
  const { root, list, add } = nestedWidget()
  const controller = buildController(root)
  clickAdd(controller, add)
  const row = list.children[0]
  const remove = row.querySelectorAll("button")[0]

  controller.nestedRemove({ currentTarget: remove, preventDefault: () => {} })

  expect(list.children.length).toBe(0)
})

test("nestedRemove on a PERSISTED row ([_destroy] present) marks it and hides the row", () => {
  const { root, list } = nestedWidget()
  const row = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
  const destroy = new FakeNode({
    tag: "input",
    type: "hidden",
    name: "order[line_items_attributes][0][_destroy]",
    value: "0",
  })
  const remove = new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#nestedRemove" } })
  row.append(destroy, remove)
  list.append(row)
  const controller = buildController(root)

  controller.nestedRemove({ currentTarget: remove, preventDefault: () => {} })

  expect(list.children.length).toBe(1)
  expect(destroy.value).toBe("1")
  expect(row.hidden).toBe(true)
  // The set-value + dispatch contract (issue #183): dirty tracking/compute see it.
  expect(destroy.dispatched.some((e) => e.type === "input")).toBe(true)
})

test("nestedRemove outside any row wrapper is a no-op", () => {
  const { root, list, add } = nestedWidget()
  const stray = new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#nestedRemove" } })
  root.append(stray)
  const controller = buildController(root)
  clickAdd(controller, add)

  controller.nestedRemove({ currentTarget: stray, preventDefault: () => {} })

  expect(list.children.length).toBe(1)
})

test("nestedRemove never escapes this root walking up (a root inside ANOTHER collection's row)", () => {
  // <div data-reactive-nested-row> (the OUTER page's row)
  //   <div data-controller=reactive id=form-root>…<button nestedRemove></button></div>
  // </div>
  const outerRow = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
  const outerList = new FakeNode({ tag: "div" })
  outerList.append(outerRow)
  const root = new FakeNode({ tag: "div", id: "form-root", controller: "reactive" })
  const stray = new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#nestedRemove" } })
  root.append(stray)
  outerRow.append(root)
  const controller = buildController(root)

  controller.nestedRemove({ currentTarget: stray, preventDefault: () => {} })

  expect(outerList.children.length).toBe(1)
})
