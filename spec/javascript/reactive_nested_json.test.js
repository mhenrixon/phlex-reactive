// Unit tests for JSON-mode draft nested rows (issue #208) — reactive_nested_list
// with `as: :json`. The rows are still real DOM inputs (add clones the template,
// remove drops the row), but the client mirrors every owned row into ONE hidden
// JSON field on every add/remove/input — for an app whose controller parses a
// serialized JSON param (JSON.parse(params[:order][:todos])) instead of Rails'
// accepts_nested_attributes_for. Each row's JSON keys are inferred from the
// trailing bracket segment of its inputs' names (…[title] → "title").
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

// A minimal DOM node — the same shape reactive_nested.test.js uses, kept local
// so the two suites don't couple. setAttribute keeps name/id coherent; matches
// handles the selectors the JSON sync queries ([data-…], [name="…"], tag lists,
// [_destroy] ends-with).
class FakeNode {
  constructor(opts = {}) {
    const { tag = "div", id = "", name = null, type = null, value = "", controller = null, attrs = {} } = opts
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
    const nameEq = selector.match(/^\[name="(.*)"\]$/)
    if (nameEq) return this.name === nameEq[1]
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
    if (attrName === "name") return void (this.name = String(attrValue))
    if (attrName === "id") return void (this.id = String(attrValue))
    this.attrs[attrName] = String(attrValue)
  }
  hasAttribute(attrName) {
    return attrName in this.attrs
  }
  dispatchEvent(event) {
    this.dispatched.push(event)
    return true
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

// The JSON-mode template row: two named inputs. In JSON mode the scope prefix
// is "order" and the assoc is "todos" — the names carry the JSON keys in their
// trailing bracket segment.
function jsonRowTemplate(assoc = "todos", scope = "order") {
  const proto = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
  proto.append(
    new FakeNode({ tag: "input", name: `${scope}[${assoc}_attributes][NEW_ROW][title]`, value: "" }),
    new FakeNode({ tag: "input", name: `${scope}[${assoc}_attributes][NEW_ROW][priority]`, value: "" }),
    new FakeNode({ tag: "button", attrs: { "data-action": "click->reactive#nestedRemove" } }),
  )
  const template = new FakeNode({ tag: "template", attrs: { "data-reactive-nested-template": assoc } })
  template.content = { firstElementChild: proto }
  return template
}

// A JSON-mode widget: the container carries BOTH the plain list marker and the
// json-mode marker + hidden-field selector, plus the hidden field itself.
function jsonWidget({ assoc = "todos", scope = "order" } = {}) {
  const root = new FakeNode({ tag: "div", id: "form-root", controller: "reactive" })
  const list = new FakeNode({
    tag: "div",
    attrs: {
      "data-reactive-nested-list": assoc,
      "data-reactive-nested-json": assoc,
      "data-reactive-nested-json-field": `[name="${scope}[${assoc}]"]`,
    },
  })
  const field = new FakeNode({ tag: "input", type: "hidden", name: `${scope}[${assoc}]`, value: "" })
  const add = new FakeNode({
    tag: "button",
    attrs: { "data-action": "click->reactive#nestedAdd", "data-reactive-association-param": assoc },
  })
  root.append(field, list, add, jsonRowTemplate(assoc, scope))
  return { root, list, field, add }
}

function clickAdd(controller, add) {
  controller.nestedAdd({ currentTarget: add, preventDefault: () => {} })
}
function fill(row, key, value) {
  const input = row.querySelectorAll("input").find((i) => (i.name ?? "").endsWith(`[${key}]`))
  input.value = value
  return input
}

test("nestedAdd on a JSON list syncs the hidden field to a JSON array (keys inferred from names)", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)

  clickAdd(controller, add)
  const row = list.children[0]
  fill(row, "title", "Buy milk")
  fill(row, "priority", "high")
  // An owned input event re-syncs the field.
  controller.syncNestedJson?.({ target: row.querySelectorAll("input")[0] })

  const parsed = JSON.parse(field.value)
  expect(parsed).toEqual([{ title: "Buy milk", priority: "high" }])
})

test("the hidden field carries one object per surviving row, in DOM order", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)

  clickAdd(controller, add)
  clickAdd(controller, add)
  fill(list.children[0], "title", "first")
  fill(list.children[1], "title", "second")
  controller.syncNestedJson({ target: list.children[1].querySelectorAll("input")[0] })

  const parsed = JSON.parse(field.value)
  expect(parsed.map((o) => o.title)).toEqual(["first", "second"])
})

test("nestedRemove on a JSON draft row drops it from the field (an absent row IS the removal)", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)
  clickAdd(controller, add)
  clickAdd(controller, add)
  fill(list.children[0], "title", "keep")
  fill(list.children[1], "title", "drop")
  const dropRow = list.children[1]
  const removeBtn = dropRow.querySelectorAll("button")[0]

  controller.nestedRemove({ currentTarget: removeBtn, preventDefault: () => {} })

  const parsed = JSON.parse(field.value)
  expect(parsed).toEqual([{ title: "keep", priority: "" }])
})

test("the field write dispatches a bubbling input (the set-value + dispatch contract, #183)", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)

  clickAdd(controller, add)
  fill(list.children[0], "title", "x")
  controller.syncNestedJson({ target: list.children[0].querySelectorAll("input")[0] })

  expect(field.dispatched.some((e) => e.type === "input")).toBe(true)
})

test("a hidden/_destroy-marked row is EXCLUDED from the JSON array", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)
  clickAdd(controller, add)
  clickAdd(controller, add)
  fill(list.children[0], "title", "visible")
  fill(list.children[1], "title", "gone")
  list.children[1].hidden = true

  controller.syncNestedJson({ target: list.children[0].querySelectorAll("input")[0] })

  const parsed = JSON.parse(field.value)
  expect(parsed).toEqual([{ title: "visible", priority: "" }])
})

test("a PLAIN (accepts_nested_attributes_for) list never touches any JSON field", () => {
  // No json marker → nestedAdd behaves exactly as before; syncNestedJson is a no-op.
  const root = new FakeNode({ tag: "div", id: "form-root", controller: "reactive" })
  const list = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-list": "line_items" } })
  const stray = new FakeNode({ tag: "input", type: "hidden", name: "order[line_items]", value: "UNTOUCHED" })
  const add = new FakeNode({
    tag: "button",
    attrs: { "data-action": "click->reactive#nestedAdd", "data-reactive-association-param": "line_items" },
  })
  const proto = new FakeNode({ tag: "div", attrs: { "data-reactive-nested-row": "" } })
  proto.append(new FakeNode({ tag: "input", name: "order[line_items_attributes][NEW_ROW][quantity]" }))
  const template = new FakeNode({ tag: "template", attrs: { "data-reactive-nested-template": "line_items" } })
  template.content = { firstElementChild: proto }
  root.append(stray, list, add, template)
  const controller = buildController(root)

  clickAdd(controller, add)
  controller.syncNestedJson({ target: list.children[0].querySelectorAll("input")[0] })

  expect(stray.value).toBe("UNTOUCHED")
})

test("syncNestedJson ignores an input in a NESTED reactive root (issue #15 ownership)", () => {
  const { root, list, field, add } = jsonWidget()
  const controller = buildController(root)
  clickAdd(controller, add)
  fill(list.children[0], "title", "mine")
  controller.syncNestedJson({ target: list.children[0].querySelectorAll("input")[0] })
  const before = field.value

  // An input that belongs to a nested reactive root must not drive THIS field.
  const inner = new FakeNode({ tag: "div", id: "inner", controller: "reactive" })
  const foreign = new FakeNode({ tag: "input", name: "order[todos_attributes][NEW_ROW][title]", value: "foreign" })
  inner.append(foreign)
  root.append(inner)
  controller.syncNestedJson({ target: foreign })

  expect(field.value).toBe(before)
})
