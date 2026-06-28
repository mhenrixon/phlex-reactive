// Unit test for the multipart/FormData request path (issue #34).
//
// When a reactive root contains a POPULATED <input type="file">, the action
// can't be sent as JSON (JSON.stringify drops the File). The controller instead
// builds a FormData body: `token` + `act` as flat fields, scalar params
// bracketed (params[caption]), and each chosen file appended (params[file], or
// params[pages][] for a multiple input). The Content-Type header is OMITTED so
// the browser sets the multipart boundary; CSRF + connection-id headers still
// ride along. With NO file present, the JSON path is unchanged.
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

// A DOM-ish node faithful enough for #collectFields() + the file detection:
//   - matches/closest for the reactive-root + field-owner predicates
//   - querySelectorAll for descendant named fields
//   - a file input exposes type === "file" and a `files` array (FileList-ish)
class FakeNode {
  constructor({ tag = "div", name = null, type = null, value = "", checked = false, files = null, controller = null } = {}) {
    this.tag = tag.toLowerCase()
    this.name = name
    this.type = type
    this.value = value
    this.checked = checked
    this.files = files // array of File for a file input
    this.parentNode = null
    this.children = []
    this.dataset = {}
    if (controller) this.dataset.controller = controller
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

  getAttribute(attr) {
    if (attr === "name") return this.name
    return null
  }
  setAttribute() {}
  removeAttribute() {}

  matches(selector) {
    if (selector === '[data-controller~="reactive"]') {
      const c = this.dataset.controller
      return !!c && c.split(/\s+/).includes("reactive")
    }
    // #collectFields walks input[name]/select[name]/textarea[name] — a file
    // input matches here too (it has a name), and its files are read off it.
    if (selector.includes("input[name]")) {
      return ["input", "select", "textarea"].includes(this.tag) && this.name != null
    }
    if (selector.includes("lexxy-editor")) return false
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
}

function fakeFile(name, body = "x") {
  // bun has File/Blob globally; a real File is what FormData.append stores.
  return new File([body], name, { type: "text/plain" })
}

function buildController(rootEl) {
  const controller = new ReactiveController()
  controller.element = rootEl
  controller.tokenValue = "tok"
  return controller
}

function stubEnv() {
  globalThis.document = {
    querySelector: (sel) => {
      if (sel.includes("action-path")) return { content: "/reactive/actions" }
      if (sel.includes("csrf-token")) return { content: "csrf-abc" }
      return null
    },
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
}

test("a populated file input sends FormData (multipart), not JSON (issue #34)", async () => {
  const root = new FakeNode({ tag: "div", controller: "reactive" })
  const caption = new FakeNode({ tag: "input", name: "caption", value: "My receipt" })
  const file = new FakeNode({ tag: "input", type: "file", name: "file", files: [fakeFile("receipt.txt")] })
  root.append(caption, file)

  let captured = null
  globalThis.fetch = (path, opts) => {
    captured = opts
    return Promise.resolve({
      redirected: false,
      ok: true,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(""),
    })
  }
  stubEnv()

  const controller = buildController(root)
  await controller.dispatch({ params: { action: "upload", params: "{}" }, preventDefault: () => {} })

  // The body is FormData, not a JSON string.
  expect(captured.body instanceof FormData).toBe(true)
  // Content-Type is NOT set by us (browser adds the multipart boundary).
  expect(captured.headers["Content-Type"]).toBeUndefined()
  // CSRF still rides along.
  expect(captured.headers["X-CSRF-Token"]).toBe("csrf-abc")

  const fd = captured.body
  expect(fd.get("token")).toBe("tok")
  expect(fd.get("act")).toBe("upload")
  // Scalar field is bracketed under params[...].
  expect(fd.get("params[caption]")).toBe("My receipt")
  // The file is appended as a real File under params[file].
  const sent = fd.get("params[file]")
  expect(sent instanceof File).toBe(true)
  expect(sent.name).toBe("receipt.txt")
})

test("a multiple file input appends every chosen file under params[name][] (issue #34)", async () => {
  const root = new FakeNode({ tag: "div", controller: "reactive" })
  const pages = new FakeNode({
    tag: "input",
    type: "file",
    name: "pages",
    files: [fakeFile("page1.txt"), fakeFile("page2.txt")],
  })
  root.append(pages)

  let captured = null
  globalThis.fetch = (path, opts) => {
    captured = opts
    return Promise.resolve({
      redirected: false,
      ok: true,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(""),
    })
  }
  stubEnv()

  const controller = buildController(root)
  await controller.dispatch({ params: { action: "upload_pages", params: "{}" }, preventDefault: () => {} })

  expect(captured.body instanceof FormData).toBe(true)
  const all = captured.body.getAll("params[pages][]")
  expect(all.length).toBe(2)
  expect(all.map((f) => f.name)).toEqual(["page1.txt", "page2.txt"])
})

test("an EMPTY file input (no file chosen) keeps the JSON path (issue #34)", async () => {
  const root = new FakeNode({ tag: "div", controller: "reactive" })
  const caption = new FakeNode({ tag: "input", name: "caption", value: "no file" })
  const file = new FakeNode({ tag: "input", type: "file", name: "file", files: [] })
  root.append(caption, file)

  let captured = null
  globalThis.fetch = (path, opts) => {
    captured = opts
    return Promise.resolve({
      redirected: false,
      ok: true,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(""),
    })
  }
  stubEnv()

  const controller = buildController(root)
  await controller.dispatch({ params: { action: "upload", params: "{}" }, preventDefault: () => {} })

  // No file chosen → unchanged JSON body, Content-Type application/json.
  expect(typeof captured.body).toBe("string")
  expect(captured.headers["Content-Type"]).toBe("application/json")
  const parsed = JSON.parse(captured.body)
  expect(parsed.params.caption).toBe("no file")
  // The empty file input's fake-path value must NOT leak in as a scalar.
  expect(parsed.params.file).toBeUndefined()
})
