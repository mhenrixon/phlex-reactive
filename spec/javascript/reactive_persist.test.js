// Unit tests for reactive_persist (issue #239) — the client-only localStorage
// draft over a root's OWNED fields. The root carries ONE JSON attr
// (data-reactive-persist = {key, ttl, debounce[, fields][, restore]}); the
// controller writes a snapshot of every persistable owned control on `input`
// (trailing-edge debounce) and `change` (immediate), flushes a pending write on
// disconnect, restores the draft FIRST in connect() (so every later seed —
// show/on-complete/filter/compute — reads the restored DOM; no synthetic
// events, no morph re-restore), and clears it on a successful turbo:submit-end
// of the owning form, on TTL expiry, or via the persist_clear op. The
// persist_state op merges a flat state bag into the same draft.
//
// Uses happy-dom for a real DOM (closest/contains/select multiple/CustomEvent)
// and a Map-backed localStorage stub so storage failures can be simulated.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach, afterEach } from "bun:test"
import { Window } from "happy-dom"

let ReactiveController

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({ Controller: class {} }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
})

const REAL = {
  document: globalThis.document,
  window: globalThis.window,
  localStorage: globalThis.localStorage,
  setTimeout: globalThis.setTimeout,
  clearTimeout: globalThis.clearTimeout,
  now: Date.now,
  info: console.info,
  warn: console.warn,
  CustomEvent: globalThis.CustomEvent,
  HTMLFormElement: globalThis.HTMLFormElement,
}

let window, storage, timers, now, infos, warns

// Map-backed localStorage with call counters and a throw switch.
function makeStorage() {
  const map = new Map()
  const stub = {
    calls: { get: 0, set: 0, remove: 0 },
    throws: false,
    getItem(k) {
      stub.calls.get++
      if (stub.throws) throw new Error("SecurityError")
      return map.has(k) ? map.get(k) : null
    },
    setItem(k, v) {
      stub.calls.set++
      if (stub.throws) throw new Error("QuotaExceededError")
      map.set(k, String(v))
    },
    removeItem(k) {
      stub.calls.remove++
      if (stub.throws) throw new Error("SecurityError")
      map.delete(k)
    },
    raw: (k) => map.get(k),
    json: (k) => (map.has(k) ? JSON.parse(map.get(k)) : null),
    seed: (k, v) => map.set(k, JSON.stringify(v)),
  }
  return stub
}

beforeEach(() => {
  window = new Window()
  globalThis.document = window.document
  globalThis.window = window
  globalThis.CustomEvent = window.CustomEvent
  globalThis.HTMLFormElement = window.HTMLFormElement
  storage = makeStorage()
  globalThis.localStorage = storage
  timers = []
  globalThis.setTimeout = (fn, ms) => {
    timers.push({ fn, ms, id: timers.length + 1 })
    return timers.length
  }
  globalThis.clearTimeout = (id) => {
    timers = timers.filter((t) => t.id !== id)
  }
  now = 1_000_000
  Date.now = () => now
  infos = []
  warns = []
  console.info = (...a) => infos.push(a.join(" "))
  console.warn = (...a) => warns.push(a.join(" "))
})

afterEach(() => {
  globalThis.document = REAL.document
  globalThis.window = REAL.window
  globalThis.localStorage = REAL.localStorage
  globalThis.setTimeout = REAL.setTimeout
  globalThis.clearTimeout = REAL.clearTimeout
  globalThis.CustomEvent = REAL.CustomEvent
  globalThis.HTMLFormElement = REAL.HTMLFormElement
  Date.now = REAL.now
  console.info = REAL.info
  console.warn = REAL.warn
})

function drainTimers() {
  const due = timers
  timers = []
  due.forEach((t) => t.fn())
}

const KEY = "phlex-reactive:persist:apply"
const PAYLOAD = { key: "apply", ttl: 60, debounce: 300 }

function mount(html, { payload = PAYLOAD, rootAttrs = "", form = true } = {}) {
  const attr = payload === null ? "" : `data-reactive-persist='${JSON.stringify(payload)}'`
  const root = `<div id="pf" data-controller="reactive" ${attr} ${rootAttrs}>${html}</div>`
  document.body.innerHTML = form ? `<form id="f">${root}</form><form id="other"></form>` : root
  const el = document.getElementById("pf")
  const controller = new ReactiveController()
  controller.element = el
  controller.tokenValue = "tok"
  return { controller, el, q: (sel) => el.querySelector(sel) }
}

const FORM = `
  <input type="text" name="form[name]">
  <input type="radio" name="form[size]" value="s">
  <input type="radio" name="form[size]" value="l">
  <input type="checkbox" name="form[gift]">
  <select multiple name="form[tags][]"><option value="a">a</option><option value="b">b</option></select>
  <input type="hidden" name="form[tz]" value="UTC">
  <input type="password" name="form[pw]" value="secret">
  <input type="file" name="form[doc]">
  <input type="submit" name="commit" value="Go">
  <input type="text" name="fuckery" data-reactive-persist="off" value="">
  <div data-controller="reactive" id="nested"><input type="text" name="inner" value="x"></div>
`

function fire(el, type) {
  el.dispatchEvent(new window.Event(type, { bubbles: true }))
}

// --- gating ---------------------------------------------------------------

test("a root without reactive_persist touches no storage and installs no timer", () => {
  const { controller, q } = mount(FORM, { payload: null })
  controller.connect()
  q('[name="form[name]"]').value = "Ada"
  fire(q('[name="form[name]"]'), "input")
  drainTimers()
  expect(storage.calls).toEqual({ get: 0, set: 0, remove: 0 })
})

test("a malformed payload warns once and disables persistence", () => {
  document.body.innerHTML = `<div id="pf" data-controller="reactive" data-reactive-persist="{oops"></div>`
  const controller = new ReactiveController()
  controller.element = document.getElementById("pf")
  controller.connect()
  expect(warns.some((w) => w.includes("reactive_persist"))).toBe(true)
  expect(storage.calls.get).toBe(0)
})

// --- write ----------------------------------------------------------------

test("input debounces (trailing edge) and writes the owned, persistable snapshot", () => {
  const { controller, q } = mount(FORM)
  controller.connect()
  q('[name="form[name]"]').value = "Ada"
  fire(q('[name="form[name]"]'), "input")
  expect(storage.calls.set).toBe(0)
  expect(timers.at(-1).ms).toBe(300)
  q('[name="form[size]"][value="l"]').checked = true
  q('[name="form[gift]"]').checked = true
  q('option[value="b"]').selected = true
  drainTimers()
  const draft = storage.json(KEY)
  expect(draft.v).toBe(1)
  expect(draft.savedAt).toBe(now)
  expect(draft.fields).toEqual({
    "form[name]": "Ada",
    "form[size]": "l",
    "form[gift]": true,
    "form[tags][]": ["b"],
  })
  // never: hidden, password, file, submit, the skip marker, a nested root's field
  for (const absent of ["form[tz]", "form[pw]", "form[doc]", "commit", "fuckery", "inner"]) {
    expect(draft.fields).not.toHaveProperty(absent)
  }
})

test("change writes immediately and cancels a pending debounce", () => {
  const { controller, q } = mount(FORM)
  controller.connect()
  fire(q('[name="form[name]"]'), "input")
  expect(timers.length).toBe(1)
  q('[name="form[gift]"]').checked = true
  fire(q('[name="form[gift]"]'), "change")
  expect(timers.length).toBe(0)
  expect(storage.json(KEY).fields["form[gift]"]).toBe(true)
})

test("fields: narrows the snapshot to the declared names", () => {
  const { controller, q } = mount(FORM, { payload: { ...PAYLOAD, fields: ["form[name]"] } })
  controller.connect()
  q('[name="form[name]"]').value = "Ada"
  q('[name="form[gift]"]').checked = true
  fire(q('[name="form[gift]"]'), "change")
  expect(storage.json(KEY).fields).toEqual({ "form[name]": "Ada" })
})

test("an unchecked radio group is stored as null (so restore leaves it alone)", () => {
  const { controller, q } = mount(FORM)
  controller.connect()
  fire(q('[name="form[name]"]'), "change")
  expect(storage.json(KEY).fields["form[size]"]).toBeNull()
})

test("disconnect flushes a pending debounce synchronously", () => {
  const { controller, q } = mount(FORM)
  controller.connect()
  q('[name="form[name]"]').value = "Ad"
  fire(q('[name="form[name]"]'), "input")
  expect(storage.calls.set).toBe(0)
  controller.disconnect()
  expect(storage.json(KEY).fields["form[name]"]).toBe("Ad")
  expect(timers.length).toBe(0)
})

// --- restore --------------------------------------------------------------

function seedDraft(fields, extra = {}) {
  storage.seed(KEY, { v: 1, savedAt: now - 1000, fields, ...extra })
}

test("connect restores the draft into BLANK owned controls and leaves server values alone", () => {
  seedDraft({ "form[name]": "Ada", "form[size]": "l", "form[gift]": true, "form[tags][]": ["a", "b"] })
  const { controller, q } = mount(FORM.replace('name="form[name]"', 'name="form[name]" value="Server"'))
  controller.connect()
  expect(q('[name="form[name]"]').value).toBe("Server") // non-blank server value wins
  expect(q('[name="form[size]"][value="l"]').checked).toBe(true)
  expect(q('[name="form[gift]"]').checked).toBe(true)
  expect(q('option[value="a"]').selected).toBe(true)
  expect(q('option[value="b"]').selected).toBe(true)
  // the restore itself never writes back (no clobbering the draft with blanks)
  expect(storage.calls.set).toBe(0)
})

test("restore: always overwrites a server-rendered value", () => {
  seedDraft({ "form[name]": "Ada" })
  const { controller, q } = mount(FORM.replace('name="form[name]"', 'name="form[name]" value="Server"'), {
    payload: { ...PAYLOAD, restore: "always" },
  })
  controller.connect()
  expect(q('[name="form[name]"]').value).toBe("Ada")
})

test("a draft never reaches an excluded control", () => {
  seedDraft({ "form[pw]": "leak", "form[tz]": "Mars", fuckery: "bot", inner: "nope", "form[name]": "" })
  const { controller, q } = mount(FORM.replace('name="form[pw]" value="secret"', 'name="form[pw]"'))
  controller.connect()
  expect(q('[name="form[pw]"]').value).toBe("")
  expect(q('[name="form[tz]"]').value).toBe("UTC")
  expect(q('[name="fuckery"]').value).toBe("")
  expect(q('[name="inner"]').value).toBe("x")
})

test("restore stamps the state bag on the root and emits reactive:persist-restored", () => {
  seedDraft({ "form[name]": "Ada" }, { state: { step: 2 } })
  const { controller, el } = mount(FORM)
  const seen = []
  el.addEventListener("reactive:persist-restored", (e) => seen.push(e.detail))
  controller.connect()
  expect(el.getAttribute("data-reactive-persist-state")).toBe('{"step":2}')
  expect(seen).toEqual([{ key: "apply", fields: { "form[name]": "Ada" }, state: { step: 2 } }])
})

test("no event and no attr when there is no draft", () => {
  const { controller, el } = mount(FORM)
  const seen = []
  el.addEventListener("reactive:persist-restored", (e) => seen.push(e.detail))
  controller.connect()
  expect(seen).toEqual([])
  expect(el.hasAttribute("data-reactive-persist-state")).toBe(false)
})

test("an expired draft is removed on read and not restored", () => {
  storage.seed(KEY, { v: 1, savedAt: now - 61_000, fields: { "form[name]": "Old" } })
  const { controller, q } = mount(FORM)
  controller.connect()
  expect(q('[name="form[name]"]').value).toBe("")
  expect(storage.raw(KEY)).toBeUndefined()
})

test("a draft with another schema version or malformed JSON is discarded silently", () => {
  storage.seed(KEY, { v: 2, savedAt: now, fields: { "form[name]": "Future" } })
  let m = mount(FORM)
  m.controller.connect()
  expect(m.q('[name="form[name]"]').value).toBe("")

  storage.setItem(KEY, "{nope")
  m = mount(FORM)
  m.controller.connect()
  expect(m.q('[name="form[name]"]').value).toBe("")
  expect(warns).toEqual([])
})

test("the restore runs BEFORE the show seed, so a reactive_show section reads the restored value", () => {
  seedDraft({ "form[size]": "l" })
  const show = JSON.stringify({ any: [[{ field: "form[size]", equals: "l" }]] })
  const { controller, q } = mount(`${FORM}<div id="sec" data-reactive-show='${show}' hidden>large</div>`)
  controller.connect()
  expect(q("#sec").hidden).toBe(false)
})

test("a restore never FIRES reactive_on_complete (arm-without-fire)", () => {
  seedDraft({ "form[name]": "123456" })
  const oc = JSON.stringify([{ any: [[{ field: "form[name]", len_eq: 6 }]], ops: [["add_class", { to: "@root", name: "done" }]] }])
  const { controller, el } = mount(FORM, { rootAttrs: `data-reactive-on-complete='${oc}'` })
  controller.connect()
  expect(el.classList.contains("done")).toBe(false)
})

test("turbo:morph-element does NOT re-restore (a morph is server truth)", () => {
  const { controller, el, q } = mount(FORM)
  controller.connect()
  seedDraft({ "form[name]": "Later" })
  el.dispatchEvent(new window.Event("turbo:morph-element", { bubbles: true }))
  expect(q('[name="form[name]"]').value).toBe("")
})

// --- clear ----------------------------------------------------------------

function submitEnd(form, success) {
  form.dispatchEvent(new window.CustomEvent("turbo:submit-end", { bubbles: true, detail: { success } }))
}

test("a successful turbo:submit-end on the owning form clears the draft", () => {
  seedDraft({ "form[name]": "Ada" })
  const { controller } = mount(FORM)
  controller.connect()
  submitEnd(document.getElementById("f"), true)
  expect(storage.raw(KEY)).toBeUndefined()
})

test("a successful submit also drops a pending keystroke write (no resurrection on the disconnect flush)", () => {
  seedDraft({ "form[name]": "Ada" })
  const { controller, q } = mount(FORM)
  controller.connect()
  q('[name="form[name]"]').value = "Ada!"
  fire(q('[name="form[name]"]'), "input")
  submitEnd(document.getElementById("f"), true)
  controller.disconnect()
  expect(storage.raw(KEY)).toBeUndefined()
})

test("a failed submit or an unrelated form leaves the draft", () => {
  seedDraft({ "form[name]": "Ada" })
  const { controller } = mount(FORM)
  controller.connect()
  submitEnd(document.getElementById("f"), false)
  submitEnd(document.getElementById("other"), true)
  expect(storage.json(KEY).fields["form[name]"]).toBe("Ada")
})

test("disconnect removes the document-level submit-end listener", () => {
  seedDraft({ "form[name]": "Ada" })
  const { controller } = mount(FORM)
  controller.connect()
  controller.disconnect()
  submitEnd(document.getElementById("f"), true)
  expect(storage.json(KEY).fields["form[name]"]).toBe("Ada")
})

// --- ops ------------------------------------------------------------------

test("persist_state merges the bag, re-snapshots the fields and stamps the root", () => {
  seedDraft({ "form[name]": "" }, { state: { step: 1, mode: "wizard" } })
  const { controller, el, q } = mount(FORM)
  controller.connect()
  q('[name="form[name]"]').value = "Ada"
  controller.runOps({ preventDefault() {}, params: { ops: JSON.stringify([["persist_state", { to: "@root", state: { step: 2 } }]]) } })
  const draft = storage.json(KEY)
  expect(draft.state).toEqual({ step: 2, mode: "wizard" })
  expect(draft.fields["form[name]"]).toBe("Ada")
  expect(el.getAttribute("data-reactive-persist-state")).toBe('{"step":2,"mode":"wizard"}')
})

test("persist_clear removes the draft and the state attr", () => {
  seedDraft({ "form[name]": "Ada" }, { state: { step: 3 } })
  const { controller, el } = mount(FORM)
  controller.connect()
  controller.runOps({ preventDefault() {}, params: { ops: JSON.stringify([["persist_clear", { to: "@root" }]]) } })
  expect(storage.raw(KEY)).toBeUndefined()
  expect(el.hasAttribute("data-reactive-persist-state")).toBe(false)
})

test("persist_state on a root without reactive_persist warns and skips", () => {
  const { controller } = mount(FORM, { payload: null })
  controller.connect()
  controller.runOps({ preventDefault() {}, params: { ops: JSON.stringify([["persist_state", { to: "@root", state: { step: 2 } }]]) } })
  expect(storage.calls.set).toBe(0)
  expect(warns.some((w) => w.includes("persist_state"))).toBe(true)
})

// --- storage failures -----------------------------------------------------

test("a throwing storage never throws out of connect/write and stays silent without debug", () => {
  storage.throws = true
  const { controller, q } = mount(FORM)
  expect(() => controller.connect()).not.toThrow()
  q('[name="form[name]"]').value = "Ada"
  expect(() => fire(q('[name="form[name]"]'), "change")).not.toThrow()
  expect(infos).toEqual([])
})

test("with data-reactive-debug the storage failure is reported once via console.info", () => {
  storage.throws = true
  const { controller, q } = mount(FORM, { rootAttrs: 'data-reactive-debug="true"' })
  controller.connect()
  fire(q('[name="form[name]"]'), "change")
  fire(q('[name="form[name]"]'), "change")
  expect(infos.length).toBe(1)
  expect(infos[0]).toContain("reactive_persist")
})

test("a missing localStorage global disables persistence quietly", () => {
  delete globalThis.localStorage
  const { controller, q } = mount(FORM)
  expect(() => controller.connect()).not.toThrow()
  expect(() => fire(q('[name="form[name]"]'), "change")).not.toThrow()
})
