// Unit test for the overridable async confirm resolver (issue #55).
//
// Follow-up to #52. The `confirm:` gate is hardcoded to the synchronous,
// browser-native window.confirm. This adds an overridable, possibly-async hook
// — confirmResolver / setConfirmResolver — defaulting to window.confirm, so an
// app can reuse its themed Turbo.config.forms.confirm dialog for reactive
// triggers. The dispatch path becomes async-aware: it preventDefault()s up
// front (the #11 submit-trigger guarantee), then awaits the resolver and only
// enqueues on a truthy resolution. A rejected resolver enqueues nothing and
// leaks no unhandled rejection.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

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

// Reset to the default (window.confirm) resolver between tests so an override in
// one test can't leak into the next.
beforeEach(() => {
  confirmModule.setConfirmResolver((message) => Promise.resolve(globalThis.window?.confirm?.(message)))
})

test("setConfirmResolver overrides the gate; an async resolve(true) proceeds", async () => {
  const { controller, calls } = buildController()
  const seen = []
  confirmModule.setConfirmResolver((message) => {
    seen.push(message)
    return Promise.resolve(true) // a themed async dialog that the user confirms
  })

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Really delete?" },
    preventDefault: () => {},
  })
  await wait(0) // let the resolver microtask settle

  expect(seen).toEqual(["Really delete?"]) // the custom resolver saw our message
  expect(calls()).toBe(1) // resolved true → the action fires
})

test("an async resolve(false) enqueues nothing but still preventDefaults", async () => {
  const { controller, calls } = buildController()
  const order = []
  confirmModule.setConfirmResolver(() => Promise.resolve(false))

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?" },
    preventDefault: () => order.push("preventDefault"),
  })
  await wait(0)

  expect(order).toEqual(["preventDefault"]) // native default stopped up front (#11)
  expect(calls()).toBe(0) // resolved false → no round trip
})

test("a resolver that rejects enqueues nothing and leaks no unhandled rejection", async () => {
  const { controller, calls } = buildController()
  const rejections = []
  const onRej = (e) => {
    rejections.push(e)
    e?.preventDefault?.()
  }
  globalThis.addEventListener?.("unhandledrejection", onRej)
  confirmModule.setConfirmResolver(() => Promise.reject(new Error("dialog dismissed")))

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?" },
    preventDefault: () => {},
  })
  await wait(10) // give any unhandled rejection time to surface

  globalThis.removeEventListener?.("unhandledrejection", onRej)
  expect(calls()).toBe(0) // rejection → nothing enqueued
  expect(rejections).toEqual([]) // and the rejection was handled, not leaked
})

test("a synchronous (non-Promise) resolver return value still works", async () => {
  const { controller, calls } = buildController()
  confirmModule.setConfirmResolver(() => true) // returns a bare boolean, not a Promise

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?" },
    preventDefault: () => {},
  })
  await wait(0)

  expect(calls()).toBe(1) // Promise.resolve(true) under the hood → proceeds
})

test("the resolver gates debounced triggers too (async confirm + debounce)", async () => {
  const { controller, calls } = buildController()
  let resolveDialog
  confirmModule.setConfirmResolver(() => new Promise((resolve) => (resolveDialog = resolve)))

  controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Sure?", debounce: 30 },
    preventDefault: () => {},
  })

  // The dialog hasn't resolved yet, so NOTHING is scheduled — not even the timer.
  await wait(50)
  expect(calls()).toBe(0)

  // Now confirm: the debounce window starts only after the resolver settles.
  resolveDialog(true)
  await wait(0)
  await wait(50) // past the 30ms debounce
  expect(calls()).toBe(1)
})

test("the default resolver delegates to window.confirm (0.4.5 behavior)", async () => {
  const { controller, calls } = buildController()
  const seen = []
  globalThis.window.confirm = (message) => {
    seen.push(message)
    return false
  }
  // No setConfirmResolver override here — beforeEach restored the default.

  await controller.dispatch({
    target: makeTarget(),
    params: { action: "destroy", params: "{}", confirm: "Native?" },
    preventDefault: () => {},
  })
  await wait(0)

  expect(seen).toEqual(["Native?"]) // default path still calls window.confirm
  expect(calls()).toBe(0) // returned false → no round trip
})
