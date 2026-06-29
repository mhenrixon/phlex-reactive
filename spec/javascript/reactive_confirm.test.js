// Unit test for the confirm option on reactive triggers (issue #52).
//
// on(:destroy, confirm: "Sure?") gates the action behind window.confirm(message).
// Declining must bail BEFORE any fetch/enqueue (the action never runs) while
// still preventing the native default (so a submit/click can't navigate on
// cancel). Accepting proceeds exactly as today. A confirm + debounce decline
// must schedule NOTHING (the prompt runs before the debounce timer).
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

// Install a window.confirm stub returning `answer`; record the message it saw.
function stubConfirm(answer) {
  const seen = []
  globalThis.window.confirm = (message) => {
    seen.push(message)
    return answer
  }
  return seen
}

test("declining the confirm bails before any fetch (the action never runs)", async () => {
  const { controller, calls } = buildController()
  const seen = stubConfirm(false)

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Really delete?" },
    preventDefault: () => {},
  })

  expect(seen).toEqual(["Really delete?"]) // the prompt was shown with our message
  expect(calls()).toBe(0) // declined → no round trip
})

test("declining still preventDefaults (a submit/click can't navigate on cancel)", async () => {
  const { controller } = buildController()
  stubConfirm(false)
  const order = []

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?" },
    preventDefault: () => order.push("preventDefault"),
  })

  expect(order).toEqual(["preventDefault"]) // native default stopped even on cancel
})

test("accepting the confirm proceeds to the round trip", async () => {
  const { controller, calls } = buildController()
  stubConfirm(true)

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?" },
    preventDefault: () => {},
  })

  expect(calls()).toBe(1) // confirmed → the action fires
})

test("declining a confirm+debounce trigger schedules NOTHING", async () => {
  const { controller, calls } = buildController()
  stubConfirm(false)

  controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?", debounce: 50 },
    preventDefault: () => {},
  })

  await wait(80) // past the debounce window
  expect(calls()).toBe(0) // the prompt ran before the timer; cancel scheduled no dispatch
})

test("no confirm → dispatch fires immediately (unchanged behavior)", async () => {
  const { controller, calls } = buildController()
  // Even if a confirm impl exists on window, no confirm param means no prompt.
  stubConfirm(false)

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "save", params: "{}" }, // no confirm
    preventDefault: () => {},
  })

  expect(calls()).toBe(1)
})
