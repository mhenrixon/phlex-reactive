// Unit tests for the `text` client op (issue #159) — set textContent, the
// cross-root text escape:
//
//   * textContent ONLY, never innerHTML — XSS-safe by construction, strictly
//     less powerful than set_attr.
//   * Root-scoped by default (issue #15 ownership semantics, like every op);
//     global: true escapes to document — the declared way to paint a value
//     into a node OUTSIDE the component's root (a recap in another tab pane).
//   * On the reactive:js stream path, global: true opts a single op out of the
//     target-root scope (previously the stream path silently ignored it).
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll } from "bun:test"

let ReactiveController
let registerReactiveJs

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  const mod = await import("../../app/javascript/phlex/reactive/reactive_controller.js")
  ReactiveController = mod.default
  registerReactiveJs = mod.registerReactiveJs
})

// A fake text-bearing node; `closest` returns the nearest reactive root
// (`owner`) — how the ownership guard decides.
function makeEl({ owner = null, text = "" } = {}) {
  return {
    textContent: text,
    closest: () => owner,
  }
}

function makeRoot(matches = {}) {
  return {
    isConnected: true,
    id: "editor",
    getAttribute: () => null,
    contains: () => false,
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
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return controller
}

function fire(controller, ops) {
  controller.runOps({
    params: { ops },
    target: { __inside: false },
    preventDefault() {},
  })
}

// --- runOps (on_client) -------------------------------------------------------

test("text sets textContent on every owned match (value already stringified)", () => {
  const root = makeRoot()
  const a = makeEl({ owner: root })
  const b = makeEl({ owner: root })
  root.querySelectorAll = () => [a, b]
  const controller = buildController(root)

  fire(controller, [["text", { to: ".total", value: "480" }]])

  expect(a.textContent).toBe("480")
  expect(b.textContent).toBe("480")
})

test("a missing value clears the node (never writes 'undefined')", () => {
  const root = makeRoot()
  const el = makeEl({ owner: root, text: "stale" })
  root.querySelectorAll = () => [el]
  const controller = buildController(root)

  fire(controller, [["text", { to: ".total" }]])

  expect(el.textContent).toBe("")
})

test("a nested reactive root's node is NOT written (issue #15 semantics)", () => {
  const root = makeRoot()
  const nestedRoot = makeRoot()
  const mine = makeEl({ owner: root })
  const theirs = makeEl({ owner: nestedRoot, text: "keep" })
  root.querySelectorAll = () => [mine, theirs]
  const controller = buildController(root)

  fire(controller, [["text", { to: ".total", value: "480" }]])

  expect(mine.textContent).toBe("480")
  expect(theirs.textContent).toBe("keep")
})

test("global: true escapes root scoping — the cross-root text escape", () => {
  const root = makeRoot()
  const summary = makeEl({ owner: null }) // outside any reactive root
  const controller = buildController(root, { documentMatches: { "#sum_total": [summary] } })

  fire(controller, [["text", { to: "#sum_total", value: "480", global: true }]])

  expect(summary.textContent).toBe("480")
})

// --- the reactive:js stream path (reply.js / broadcast_js_to) -----------------

function stubTurbo() {
  globalThis.window = { Turbo: { StreamActions: {} } }
  return globalThis.window.Turbo.StreamActions
}

function invoke(actions, { ops, target } = {}) {
  const attrs = { "data-reactive-ops": JSON.stringify(ops) }
  if (target != null) attrs.target = target
  actions["reactive:js"].call({ getAttribute: (name) => attrs[name] ?? null })
}

test("a document-scoped stream text op paints document-wide (no target)", () => {
  const actions = stubTurbo()
  registerReactiveJs()
  const summary = makeEl()
  globalThis.document = {
    getElementById: () => null,
    querySelectorAll: (sel) => (sel === "#sum_total" ? [summary] : []),
  }

  invoke(actions, { ops: [["text", { to: "#sum_total", value: "480" }]] })

  expect(summary.textContent).toBe("480")
})

test("with a target root, a stream text op resolves WITHIN that root", () => {
  const actions = stubTurbo()
  registerReactiveJs()
  const inside = makeEl()
  const root = { id: "editor", querySelectorAll: (sel) => (sel === ".total" ? [inside] : []) }
  globalThis.document = {
    getElementById: (id) => (id === "editor" ? root : null),
    querySelectorAll: () => {
      throw new Error("must resolve within the target root, not the document")
    },
  }

  invoke(actions, { ops: [["text", { to: ".total", value: "480" }]], target: "editor" })

  expect(inside.textContent).toBe("480")
})

test("global: true escapes the target-root scope on the stream path (issue #159)", () => {
  const actions = stubTurbo()
  registerReactiveJs()
  const summary = makeEl()
  const root = {
    id: "editor",
    querySelectorAll: () => {
      throw new Error("a global op must resolve against the document, not the root")
    },
  }
  globalThis.document = {
    getElementById: (id) => (id === "editor" ? root : null),
    querySelectorAll: (sel) => (sel === "#sum_total" ? [summary] : []),
  }

  invoke(actions, { ops: [["text", { to: "#sum_total", value: "480", global: true }]], target: "editor" })

  expect(summary.textContent).toBe("480")
})

test("@root with a target still resolves to the root itself (global does not change it)", () => {
  const actions = stubTurbo()
  registerReactiveJs()
  const root = { id: "editor", textContent: "", querySelectorAll: () => [] }
  globalThis.document = {
    getElementById: (id) => (id === "editor" ? root : null),
    querySelectorAll: () => [],
  }

  invoke(actions, { ops: [["text", { to: "@root", value: "done", global: true }]], target: "editor" })

  expect(root.textContent).toBe("done")
})
