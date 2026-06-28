// Unit test for the reactive-root id guard (issue #48).
//
// The token round trip is load-bearing on the invariant "the reactive controller
// root element's id == component.id": the server targets component.id, and the
// client self-matches its NEXT token by this.element.id (#extractToken, issue #46).
// If an app puts `id:` on a CHILD instead of the `**reactive_attrs` root, the root's
// id is "" — #extractToken falls back to the first token in the body (a child's),
// and the next action POSTs a foreign token → endpoint default-deny → 403, SILENTLY.
//
// connect() warns the instant a reactive root has an empty id, so the failure
// surfaces on page load (a one-line console hint) instead of on the second click.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

let ReactiveController

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  const mod = await import("../../app/javascript/phlex/reactive/reactive_controller.js")
  ReactiveController = mod.default
})

let warnings
beforeEach(() => {
  warnings = []
  globalThis.console = { warn: (...a) => warnings.push(a.join(" ")), error: () => {} }
})

function connectWithId(id) {
  const controller = new ReactiveController()
  controller.element = { id }
  controller.connect()
  return controller
}

test("warns when the reactive root has an empty id", () => {
  connectWithId("")
  expect(warnings.length).toBe(1)
  expect(warnings[0]).toContain("phlex-reactive")
  expect(warnings[0].toLowerCase()).toContain("id")
  // points at the fix (reactive_root / id: on the same element)
  expect(warnings[0]).toContain("reactive_root")
})

test("stays silent when the reactive root has an id", () => {
  connectWithId("invoice_items")
  expect(warnings.length).toBe(0)
})
