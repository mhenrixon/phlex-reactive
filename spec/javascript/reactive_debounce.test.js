// Unit test for the debounce option on reactive triggers (issue #17).
//
// on(:update, event: "input", debounce: 50) must coalesce rapid inputs into a
// SINGLE action round trip fired after the quiet period — instead of one POST
// per keystroke. A blur flushes a pending debounced dispatch immediately. With
// no debounce declared, dispatch fires immediately (today's behavior).
//
// We count fetch() calls with REAL timers (small delays) so the coalescing is
// observed deterministically without fake-timer/microtask interplay.
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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// A trigger element stub that records blur listeners so the test can fire blur.
function makeTarget() {
  const listeners = {}
  return {
    addEventListener: (type, fn) => {
      (listeners[type] ||= []).push(fn)
    },
    removeEventListener: (type, fn) => {
      listeners[type] = (listeners[type] || []).filter((f) => f !== fn)
    },
    fire: (type) => (listeners[type] || []).slice().forEach((fn) => fn()),
  }
}

function makeRoot() {
  return {
    querySelectorAll: () => [],
    setAttribute: () => {},
    removeAttribute: () => {},
    getAttribute: () => null,
  }
}

function buildController() {
  const controller = new ReactiveController()
  controller.element = makeRoot()
  controller.tokenValue = "tok"
  let calls = 0
  globalThis.fetch = () => {
    calls++
    return Promise.resolve({
      redirected: false,
      ok: true,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(""),
    })
  }
  globalThis.document = { querySelector: () => null }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, calls: () => calls }
}

test("debounced dispatches coalesce into ONE fetch after the quiet period (issue #17)", async () => {
  const { controller, calls } = buildController()
  const target = makeTarget()

  // Five rapid "input" dispatches, 10ms apart, with a 50ms debounce.
  for (let i = 0; i < 5; i++) {
    controller.dispatch({
      target,
      params: { action: "update", params: "{}", debounce: 50 },
      preventDefault: () => {},
    })
    await wait(10)
  }

  // Still inside the window right after the burst → nothing fired yet.
  expect(calls()).toBe(0)

  await wait(120) // cross the quiet period + let the round trip run
  expect(calls()).toBe(1) // exactly ONE round trip for the whole burst
})

test("blur flushes a pending debounced dispatch immediately", async () => {
  const { controller, calls } = buildController()
  const target = makeTarget()

  controller.dispatch({
    target,
    params: { action: "update", params: "{}", debounce: 5000 },
    preventDefault: () => {},
  })
  expect(calls()).toBe(0)

  target.fire("blur") // user tabs away before the long window elapses
  await wait(20)
  expect(calls()).toBe(1) // flushed, not lost
})

test("no debounce → dispatch fires immediately (unchanged behavior)", async () => {
  const { controller, calls } = buildController()

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "save", params: "{}" }, // no debounce
    preventDefault: () => {},
  })

  expect(calls()).toBe(1)
})

test("a debounced dispatch still preventDefaults synchronously (submit safety)", () => {
  const { controller } = buildController()
  const order = []
  controller.dispatch({
    target: makeTarget(),
    params: { action: "save", params: "{}", debounce: 300 },
    preventDefault: () => order.push("preventDefault"),
  })
  // preventDefault must fire NOW (during the event), not after the debounce
  // timer — otherwise a debounced submit trigger would navigate (issue #11).
  expect(order).toEqual(["preventDefault"])
})
