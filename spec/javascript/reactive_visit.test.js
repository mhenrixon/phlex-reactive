// Unit test for the `reactive:visit` custom turbo-stream action. Response.redirect(url)
// on the server emits a <turbo-stream action="reactive:visit" data-url="…">; the client
// turns it into Turbo.visit.
//
// We call the exported registerReactiveVisit() explicitly rather than relying on the
// module's import-time side effect: bun runs all spec/javascript files in ONE process,
// so the module may already be imported (and registration already attempted, possibly
// against a window without Turbo) by the time this file's setup runs. Calling it
// directly makes the test order-independent.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeEach } from "bun:test"

let registerReactiveVisit
let visited

beforeEach(async () => {
  mock.module("@hotwired/stimulus", () => ({ Controller: class {} }))
  visited = []
  globalThis.window = {
    Turbo: {
      StreamActions: {},
      visit: (url, opts) => visited.push({ url, opts }),
    },
  }
  ;({ registerReactiveVisit } = await import("../../app/javascript/phlex/reactive/reactive_controller.js"))
  registerReactiveVisit()
})

test("registers a reactive:visit StreamAction on window.Turbo", () => {
  expect(typeof window.Turbo.StreamActions["reactive:visit"]).toBe("function")
})

test("reactive:visit navigates to the element's data-url via Turbo.visit", () => {
  const handler = window.Turbo.StreamActions["reactive:visit"]
  // Stream actions run with `this` = the <turbo-stream> element.
  handler.call({ getAttribute: (name) => (name === "data-url" ? "/todos" : null) })

  expect(visited).toEqual([{ url: "/todos", opts: { action: "advance" } }])
})

test("reactive:visit with no data-url does nothing", () => {
  const before = visited.length
  window.Turbo.StreamActions["reactive:visit"].call({ getAttribute: () => null })
  expect(visited.length).toBe(before)
})
