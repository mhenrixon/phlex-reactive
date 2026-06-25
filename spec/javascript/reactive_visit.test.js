// Unit test for the `reactive:visit` custom turbo-stream action registered by
// the reactive controller module. Response.redirect(url) on the server emits a
// <turbo-stream action="reactive:visit" data-url="…">; the client turns it into
// Turbo.visit. We assert the handler is registered on window.Turbo.StreamActions
// and navigates to data-url. (Separate file so the module imports fresh with
// window.Turbo already present — module-scope registration runs once on import.)
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll } from "bun:test"

let visited

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({ Controller: class {} }))
  visited = []
  globalThis.window = {
    Turbo: {
      StreamActions: {},
      visit: (url, opts) => visited.push({ url, opts }),
    },
  }
  // Importing the module runs registerReactiveVisit() against window.Turbo.
  await import("../../app/javascript/phlex/reactive/reactive_controller.js")
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
