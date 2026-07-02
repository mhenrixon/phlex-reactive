// Unit test for the reactive Stimulus controller's dispatch() timing.
//
// Issue #11: event.preventDefault() must be called SYNCHRONOUSLY inside
// dispatch(), while the browser is still handling the event. Deferring it into
// the request-queue microtask (the .then(() => this.#perform(...)) chain) is too
// late — a `submit` trigger natively POSTs the form and the page navigates
// before the reactive round trip runs. The browser/Turbo race that surfaces
// this isn't reproducible in the minimal dummy Rails app, so we assert the
// contract directly here.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll } from "bun:test"

let ReactiveController

beforeAll(async () => {
  // Stub @hotwired/stimulus so we can import the real controller in isolation
  // (no Stimulus, no bundler). We only need a Controller base with `element`.
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {
        this.element = makeElement()
      }
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
})

// Minimal element stub: querySelectorAll returns nothing, setAttribute is a
// no-op. Enough for #collectFields() and the aria-busy toggle not to throw
// before the (irrelevant-here) fetch.
function makeElement() {
  return {
    querySelectorAll: () => [],
    setAttribute: () => {},
    removeAttribute: () => {},
    getAttribute: () => null,
  }
}

function buildController() {
  const controller = new ReactiveController()
  // Set the element explicitly (not only via the mocked base-class constructor):
  // bun runs every spec file in one process, so another file's Controller stub
  // (with a bare constructor) can win the mock.module race.
  controller.element = makeElement()
  controller.tokenValue = "tok"
  // Avoid a real network call in the deferred #perform: stub fetch to reject.
  globalThis.fetch = () => Promise.reject(new Error("no network in unit test"))
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  return controller
}

test("dispatch() calls preventDefault synchronously (issue #11)", () => {
  const controller = buildController()
  const calls = []
  const event = {
    params: { action: "save", params: "{}" },
    preventDefault: () => calls.push("preventDefault"),
  }

  const queue = controller.dispatch(event)
  // Swallow the deferred #perform rejection (fetch stubbed to reject); we only
  // care that preventDefault already ran by this point — BEFORE any await.
  if (queue && queue.catch) queue.catch(() => {})

  // The decisive assertion: preventDefault fired during the synchronous call,
  // not in a later microtask. Pre-fix (preventDefault inside #perform) this is
  // empty here because #perform is deferred behind .then().
  expect(calls).toEqual(["preventDefault"])
})

test("dispatch() ignores an event with no action (no preventDefault)", () => {
  const controller = buildController()
  const calls = []
  const event = {
    params: {},
    preventDefault: () => calls.push("preventDefault"),
  }

  controller.dispatch(event)
  // No action declared → nothing to do, and we must not preventDefault a trigger
  // that isn't ours.
  expect(calls).toEqual([])
})
