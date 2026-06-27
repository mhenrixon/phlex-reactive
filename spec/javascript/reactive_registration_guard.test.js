// Unit test for the registration guard (issue #26 part 2).
//
// In a `lazyLoadControllersFrom("controllers", application)` app, only
// controllers under app/javascript/controllers/ get registered. The gem's
// controller lives outside that dir, so `data-controller="reactive"` silently
// does nothing — components render but no action ever fires, with no error.
//
// checkReactiveRegistration() detects exactly this: reactive elements present in
// the DOM, but no reactive controller ever connected. It warns; otherwise stays
// silent.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach, afterEach } from "bun:test"

let mod

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  mod = await import("../../app/javascript/phlex/reactive/reactive_controller.js")
})

let warnings
beforeEach(() => {
  warnings = []
  globalThis.console = { warn: (...a) => warnings.push(a.join(" ")), error: () => {} }
  mod.__resetReactiveRegistrationForTest()
})

afterEach(() => {
  delete globalThis.document
})

function docWithReactiveEls(count) {
  return {
    querySelectorAll: (sel) =>
      sel.includes("reactive") ? new Array(count).fill({}) : [],
  }
}

test("warns when reactive elements exist but no controller connected", () => {
  globalThis.document = docWithReactiveEls(2)
  mod.checkReactiveRegistration()
  expect(warnings.length).toBe(1)
  expect(warnings[0]).toContain("phlex-reactive")
  expect(warnings[0].toLowerCase()).toContain("register")
})

test("stays silent when a controller has connected", () => {
  globalThis.document = docWithReactiveEls(2)
  mod.__markReactiveConnectedForTest()
  mod.checkReactiveRegistration()
  expect(warnings.length).toBe(0)
})

test("stays silent when there are no reactive elements at all", () => {
  globalThis.document = docWithReactiveEls(0)
  mod.checkReactiveRegistration()
  expect(warnings.length).toBe(0)
})
