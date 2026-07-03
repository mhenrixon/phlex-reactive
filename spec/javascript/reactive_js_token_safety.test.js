// Token-safety pin for the `reactive:js` stream action (issue #97).
//
// A reply may carry a `reactive:js` stream that TARGETS the component's own id
// (e.g. reply.morph.js(js.focus("@root"))). #extractToken must NOT treat that
// stream as a token-bearing self-render: its action name is "reactive:js", not
// replace/update/reactive:token, so it can never match the self-token or
// token-only regexes. If it DID, a stale/absent token would be adopted and the
// next dispatch would 400.
//
// We drive two real dispatch()es. The first response is a genuine self morph
// (carrying SELF-FRESH) PLUS a trailing reactive:js stream at the SAME target.
// The second dispatch must POST SELF-FRESH — proving the reactive:js stream
// neither shadowed nor overrode the real self token.
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

function fakeRoot(id) {
  const attrs = {}
  return {
    id,
    querySelectorAll: () => [],
    setAttribute: (name, value) => {
      attrs[name] = value
    },
    removeAttribute: (name) => {
      delete attrs[name]
    },
    getAttribute: (name) => attrs[name] ?? null,
  }
}

function buildController(rootEl, initialToken) {
  const controller = new ReactiveController()
  controller.element = rootEl
  controller.tokenValue = initialToken
  return controller
}

function stubEnv() {
  globalThis.document = {
    querySelector: (sel) => {
      if (sel.includes("action-path")) return { content: "/reactive/actions" }
      if (sel.includes("csrf-token")) return { content: "csrf-abc" }
      return null
    },
    dispatchEvent: () => {},
  }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
}

function stubFetchReturning(body, captured) {
  globalThis.fetch = (path, opts) => {
    captured.push(JSON.parse(opts.body))
    return Promise.resolve({
      redirected: false,
      ok: true,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(body),
    })
  }
}

test("a reactive:js stream at OUR target does not shadow the real self token", async () => {
  const root = fakeRoot("counter")
  const controller = buildController(root, "TOKEN-INITIAL")
  stubEnv()

  // A real self morph carrying SELF-FRESH, then a reactive:js op stream at the
  // SAME target. Ordering mirrors the endpoint (ops LAST).
  const body =
    `<turbo-stream action="replace" method="morph" target="counter">` +
    `<template><div id="counter" data-controller="reactive" data-reactive-token-value="SELF-FRESH">1</div></template>` +
    `</turbo-stream>` +
    `<turbo-stream action="reactive:js" target="counter" data-reactive-ops="[[&quot;focus&quot;,{&quot;to&quot;:&quot;@root&quot;}]]"></turbo-stream>`

  const captured = []
  stubFetchReturning(body, captured)

  await controller.dispatch({ params: { action: "save", params: "{}" }, preventDefault: () => {} })
  await controller.dispatch({ params: { action: "save", params: "{}" }, preventDefault: () => {} })

  expect(captured[1].token).toBe("SELF-FRESH")
})

test("a reactive:js stream ALONE at our target never becomes the next token", async () => {
  // No self-render present — only a reactive:js op stream targeting our id.
  // Since reactive:js is not a self-render action, #extractToken finds no self
  // token and KEEPS the existing one (never adopts anything from the js stream).
  const root = fakeRoot("counter")
  const controller = buildController(root, "TOKEN-INITIAL")
  stubEnv()

  const body =
    `<turbo-stream action="reactive:js" target="counter" data-reactive-ops="[[&quot;add_class&quot;,{&quot;to&quot;:&quot;@root&quot;,&quot;classes&quot;:[&quot;flash&quot;]}]]"></turbo-stream>`

  const captured = []
  stubFetchReturning(body, captured)

  await controller.dispatch({ params: { action: "ping", params: "{}" }, preventDefault: () => {} })
  await controller.dispatch({ params: { action: "ping", params: "{}" }, preventDefault: () => {} })

  expect(captured[1].token).toBe("TOKEN-INITIAL")
})
