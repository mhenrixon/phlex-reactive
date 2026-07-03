// Unit tests for client debug mode (issue #108) — "devtools-lite".
//
// When the reactive root carries data-reactive-debug="true" (stamped by the Ruby
// reactive_attrs only when Phlex::Reactive.debug is on), the generic controller
// console.groups EVERY dispatch with an observability trace of the round trip:
//
//   ▼ reactive TodoItemComponent#rename → 200 (48ms)
//       params: [title] + collected: [title]
//       streams: replace → #todo_42   token: refreshed ✓
//
// The trace carries NAMES + outcomes ONLY — never the signed token VALUE, never
// field VALUES (they may be sensitive). Off (no attr) it must do NOTHING and, in
// particular, no response parsing (the "zero cost when off" invariant).
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

// A reactive root stub. `debug` toggles the data-reactive-debug attribute the
// controller reads to decide whether to log. `fields` are named controls the
// field walk collects (so we can assert collected NAMES appear but not values).
function makeRoot({ debug = false, id = "todo_42", fields = [] } = {}) {
  const attrs = {}
  if (debug) attrs["data-reactive-debug"] = "true"
  const root = {
    isConnected: true,
    id,
    ownerRoot: null,
    dispatchEvent: () => {},
    getAttribute: (name) => attrs[name] ?? null,
    setAttribute: (name, value) => (attrs[name] = value),
    removeAttribute: (name) => delete attrs[name],
    querySelectorAll: (selector) => {
      // The field walk queries named controls; return our stub fields ONLY for the
      // standard input/select/textarea query and [] for everything else (the
      // rich-text/contenteditable walk, busy_on, dirty scan, etc.).
      if (selector === "input[name], select[name], textarea[name]") return fields
      return []
    },
    contains: () => true,
  }
  // Each field's nearest reactive root is this element (ownership check).
  for (const f of fields) f.closest = () => root
  return root
}

// Build a controller with a scripted single fetch response.
function buildController(response, { root } = {}) {
  const controller = new ReactiveController()
  controller.element = root ?? makeRoot()
  controller.tokenValue = "tok-INITIAL-secret"
  let bodyReads = 0
  globalThis.fetch = () =>
    Promise.resolve({
      redirected: response.redirected ?? false,
      ok: response.ok ?? true,
      status: response.status ?? 200,
      headers: { get: () => response.contentType ?? "text/vnd.turbo-stream.html" },
      text: () => {
        bodyReads++
        return Promise.resolve(response.body ?? "")
      },
    })
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, bodyReads: () => bodyReads }
}

// Spy on the whole console-group family for one call, restoring after.
function captureConsole(fn) {
  const calls = { group: [], groupCollapsed: [], groupEnd: [], log: [], info: [] }
  const originals = {}
  for (const key of Object.keys(calls)) {
    originals[key] = console[key]
    console[key] = (...args) => calls[key].push(args)
  }
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      for (const key of Object.keys(calls)) console[key] = originals[key]
    })
    .then(() => calls)
}

// Every argument passed to any console method in this capture, flattened to one
// string — the surface a token/value leak would show up in.
function allConsoleText(calls) {
  return Object.values(calls)
    .flat()
    .flat()
    .map((a) => (typeof a === "string" ? a : JSON.stringify(a)))
    .join("\n")
}

function click(controller, extra = {}) {
  return controller.dispatch({
    params: { action: "rename", params: '{"title":"x"}', ...extra },
    currentTarget: null,
    preventDefault: () => {},
  })
}

const REPLACE_BODY =
  '<turbo-stream action="replace" target="todo_42"><template>' +
  '<div data-reactive-token-value="tok-FRESH-secret"></div></template></turbo-stream>'

// --- ON: the group is emitted with the right fields ------------------------

test("debug on: groups the dispatch with action, status, encoding and param/collected NAMES", async () => {
  const root = makeRoot({ debug: true, fields: [{ name: "title", value: "x", type: "text" }] })
  const { controller } = buildController({ body: REPLACE_BODY }, { root })

  const calls = await captureConsole(() => click(controller))
  const text = allConsoleText(calls)

  // A group was opened (group or groupCollapsed) and closed.
  const groupOpens = calls.group.length + calls.groupCollapsed.length
  expect(groupOpens).toBe(1)
  expect(calls.groupEnd.length).toBe(1)

  // Action + status appear in the group header/body.
  expect(text).toContain("rename")
  expect(text).toContain("200")
  // Param NAMES + collected field NAMES (names only).
  expect(text).toContain("title")
  // JSON encoding (no files chosen).
  expect(text.toLowerCase()).toContain("json")
})

test("debug on: reports the response stream actions + targets it parses from the held body", async () => {
  const root = makeRoot({ debug: true })
  const { controller, bodyReads } = buildController({ body: REPLACE_BODY }, { root })

  const calls = await captureConsole(() => click(controller))
  const text = allConsoleText(calls)

  expect(text).toContain("replace")
  expect(text).toContain("todo_42")
  // The debug branch REUSES the body #perform already read — it does not re-fetch
  // or read the stream a second time (text() called once).
  expect(bodyReads()).toBe(1)
})

test("debug on: reports a token refresh as present WITHOUT logging the token value", async () => {
  const root = makeRoot({ debug: true })
  const { controller } = buildController({ body: REPLACE_BODY }, { root })

  const calls = await captureConsole(() => click(controller))
  const text = allConsoleText(calls)

  // A refresh was detected (the response re-renders our id with a fresh token).
  expect(text.toLowerCase()).toContain("refresh")
  // …but NEITHER the old NOR the new token VALUE is ever in any console argument.
  expect(text).not.toContain("tok-FRESH-secret")
  expect(text).not.toContain("tok-INITIAL-secret")
})

test("debug on: reports NO token refresh when the response does not re-render our id", async () => {
  const root = makeRoot({ debug: true, id: "todo_42" })
  // A stream targeting a DIFFERENT id — #extractToken returns undefined for us.
  const otherBody =
    '<turbo-stream action="append" target="list_1"><template>' +
    '<div data-reactive-token-value="tok-OTHER"></div></template></turbo-stream>'
  const { controller } = buildController({ body: otherBody }, { root })

  const calls = await captureConsole(() => click(controller))
  const text = allConsoleText(calls)

  expect(text).toContain("append")
  expect(text).toContain("list_1")
  // No refresh for us — and definitely no foreign token value.
  expect(text).not.toContain("tok-OTHER")
})

test("debug on: field VALUES are never logged, only names", async () => {
  const root = makeRoot({
    debug: true,
    fields: [{ name: "title", value: "SENSITIVE-VALUE", type: "text" }],
  })
  const { controller } = buildController({ body: REPLACE_BODY }, { root })

  const calls = await captureConsole(() => click(controller, { params: '{"title":"SENSITIVE-EXPLICIT"}' }))
  const text = allConsoleText(calls)

  expect(text).toContain("title") // the NAME is fine
  expect(text).not.toContain("SENSITIVE-VALUE") // collected field value
  expect(text).not.toContain("SENSITIVE-EXPLICIT") // explicit param value
})

// --- OFF: nothing is logged, and no response parsing happens ----------------

test("debug off: nothing is grouped (no attr → no log surface)", async () => {
  const root = makeRoot({ debug: false })
  const { controller } = buildController({ body: REPLACE_BODY }, { root })

  const calls = await captureConsole(() => click(controller))

  expect(calls.group.length).toBe(0)
  expect(calls.groupCollapsed.length).toBe(0)
  expect(calls.groupEnd.length).toBe(0)
})

// --- Failure paths still log a meaningful status ----------------------------

test("debug on: a non-OK response is grouped with its status", async () => {
  const root = makeRoot({ debug: true })
  const { controller } = buildController({ ok: false, status: 403, body: "denied", contentType: "text/html" }, { root })

  const calls = await captureConsole(() => click(controller))
  const text = allConsoleText(calls)

  const groupOpens = calls.group.length + calls.groupCollapsed.length
  expect(groupOpens).toBe(1)
  expect(calls.groupEnd.length).toBe(1)
  expect(text).toContain("403")
})
