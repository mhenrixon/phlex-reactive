// Unit tests for confirm: on on_client (issue #178) — the client-op path
// (runOps) gains the SAME confirmResolver gate on() already has, reused verbatim:
//
//   * No confirm param → ops apply immediately (unchanged fast path, no prompt).
//   * confirm + resolver→truthy → ops apply exactly as an unguarded client op.
//   * confirm + resolver→falsy → ops do NOT apply (the destructive UI is cancelled).
//   * confirm + resolver throws → treated as a cancel (no ops, no unhandled rejection).
//   * preventDefault fires BEFORE the (possibly async) gate — a bare button in a
//     <form> can't submit while the dialog is pending.
//
// The gate lives in runOps (the user gesture), NEVER in #applyOps (shared with the
// server-pushed reactive:js stream, which must never prompt) — issue #178 scope.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, afterEach } from "bun:test"

let ReactiveController
let confirmModule

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
  confirmModule = await import("../../app/javascript/phlex/reactive/confirm.js")
})

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// Reset the resolver to the default (window.confirm) after every test so an
// override in one test can't leak into the next.
afterEach(() => {
  confirmModule.setConfirmResolver((message) =>
    Promise.resolve(typeof globalThis.window !== "undefined" ? globalThis.window.confirm(message) : true)
  )
})

// A DOM node whose `hidden` flag the ops flip — the observable "did the op run".
function makeEl({ owner = null } = {}) {
  const el = { hidden: false, closest: () => owner }
  return el
}

function makeRoot(matches = {}) {
  return {
    isConnected: true,
    id: "co",
    contains: (el) => el?.__inside === true,
    querySelectorAll: (sel) => matches[sel] ?? [],
  }
}

function buildController(root) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.fetch = () => {
    throw new Error("runOps must NEVER fetch")
  }
  globalThis.document = {
    querySelector: () => null,
    querySelectorAll: () => [],
    dispatchEvent: () => {},
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return controller
}

function fire(controller, { ops, confirm, outside, windowBound, target } = {}) {
  const event = {
    params: { ops, confirm, outside, window: windowBound },
    target: target ?? { __inside: false },
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
  controller.runOps(event)
  return event
}

// Install a window.confirm stub returning `answer`; record the message it saw.
function stubConfirm(answer) {
  const seen = []
  globalThis.window.confirm = (message) => {
    seen.push(message)
    return answer
  }
  return seen
}

test("no confirm param → ops apply immediately (unchanged fast path)", () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  stubConfirm(false) // even if a confirm impl exists, no param means no prompt

  fire(controller, { ops: [["hide", { to: "#x" }]] })

  expect(el.hidden).toBe(true) // ran with no dialog
})

test("confirm accepted → ops apply exactly as an unguarded client op", async () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  const seen = stubConfirm(true)

  fire(controller, { ops: [["hide", { to: "#x" }]], confirm: "Discard this draft?" })
  await wait(0) // the gate is async (Promise-wrapped) — let it settle

  expect(seen).toEqual(["Discard this draft?"]) // prompted with our message
  expect(el.hidden).toBe(true) // accepted → ops ran
})

test("confirm declined → ops do NOT apply (destructive UI cancelled)", async () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  const seen = stubConfirm(false)

  fire(controller, { ops: [["hide", { to: "#x" }]], confirm: "Discard this draft?" })
  await wait(0)

  expect(seen).toEqual(["Discard this draft?"]) // prompt was shown
  expect(el.hidden).toBe(false) // declined → ops never ran
})

test("confirm resolver throws → treated as a cancel (no ops, no unhandled rejection)", async () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  confirmModule.setConfirmResolver(() => {
    throw new Error("dialog blew up")
  })

  fire(controller, { ops: [["hide", { to: "#x" }]], confirm: "Sure?" })
  await wait(0)

  expect(el.hidden).toBe(false) // a throwing dialog cancels, like a decline
})

test("declined confirm still preventDefaults (a submit/click can't navigate on cancel)", async () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  stubConfirm(false)

  const event = fire(controller, { ops: [["hide", { to: "#x" }]], confirm: "Sure?" })

  // preventDefault happened synchronously, BEFORE the async gate resolved.
  expect(event.defaultPrevented).toBe(true)
  await wait(0)
  expect(el.hidden).toBe(false)
})

test("window-bound trigger with confirm is NOT preventDefaulted (issue #80 semantics preserved)", async () => {
  const root = makeRoot()
  const el = makeEl({ owner: root })
  root.querySelectorAll = (sel) => ({ "#x": [el] })[sel] ?? []
  const controller = buildController(root)
  stubConfirm(true)

  const event = fire(controller, {
    ops: [["hide", { to: "#x" }]],
    confirm: "Sure?",
    windowBound: true,
  })

  expect(event.defaultPrevented).toBe(false) // window-bound never preventDefaults
  await wait(0)
  expect(el.hidden).toBe(true) // accepted → still runs
})
