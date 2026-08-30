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

// --- rich editors (issue #241) --------------------------------------------
//
// Named rich-text editors (lexxy-editor, trix-editor) and bare [contenteditable]
// are persisted through their OWN value surface: an editor's `value`
// getter/setter (the same sanitizing import path a paste takes), a bare
// contenteditable's textContent. Never innerHTML. The stubs below mimic the
// VERIFIED upstream contracts (lexxy 0.9.31, action_text-trix 2.1.19):
//   lexxy-editor: name = attribute, form-associated (no hidden input),
//     `set value` throws before connectedCallback created `this.editor`,
//     `isEmpty` over ["<p><br></p>", "<p></p>", ""], fires lexxy:change.
//   trix-editor: name/value delegate to the `input=` hidden input (the Rails
//     rich_text_area shape) else the element's own name attribute,
//     `set value` → editor.loadHTML (stashed pre-connect), fires trix-change,
//     emptiness via editor.getDocument().isEmpty().
// Both are defined on the per-test happy-dom window's registry; a test that
// needs the "not yet upgraded" path defines them late.

const EMPTY_HTML = ["<p><br></p>", "<p></p>", ""]
let innerHTMLWrites, editorSets

// whenDefined resolves through happy-dom's own promise chain — let the real
// event loop turn (the stubbed global setTimeout is bypassed by Bun.sleep).
const settle = () => Bun.sleep(0)

function defineLexxy() {
  window.customElements.define(
    "lexxy-editor",
    class extends window.HTMLElement {
      connectedCallback() {
        this.editor = { update: () => {} } // upstream: the setter runs inside editor.update
        this.html ??= this.getAttribute("value") ?? "<p><br></p>"
      }
      get name() {
        return this.getAttribute("name")
      }
      get value() {
        return this.html
      }
      set value(html) {
        this.editor.update() // TypeError before connect, like upstream
        editorSets++
        this.html = html
        this.dispatchEvent(new window.CustomEvent("lexxy:change", { bubbles: true }))
      }
      get isEmpty() {
        return EMPTY_HTML.includes(this.value.trim())
      }
      set innerHTML(_html) {
        innerHTMLWrites++
      }
    },
  )
}

function defineTrix() {
  window.customElements.define(
    "trix-editor",
    class extends window.HTMLElement {
      connectedCallback() {
        this.setAttribute("contenteditable", "") // upstream makeEditable(this)
        this.editor = {
          loadHTML: (html) => this.setFormValue(html),
          getDocument: () => ({ isEmpty: () => this.value === "" }),
        }
      }
      get inputElement() {
        return this.hasAttribute("input") ? document.getElementById(this.getAttribute("input")) : undefined
      }
      get name() {
        return this.inputElement ? this.inputElement.name : this.getAttribute("name")
      }
      get value() {
        return this.inputElement ? this.inputElement.value : (this.formValue ?? "")
      }
      set value(html) {
        this.defaultValue = html
        editorSets++
        this.editor?.loadHTML(html)
      }
      setFormValue(html) {
        if (this.inputElement) this.inputElement.value = html
        else this.formValue = html
        this.dispatchEvent(new window.CustomEvent("trix-change", { bubbles: true }))
      }
      set innerHTML(_html) {
        innerHTMLWrites++
      }
    },
  )
}

function mountEditors(html, opts = {}) {
  globalThis.customElements = window.customElements
  innerHTMLWrites = 0
  editorSets = 0
  if (!opts.late) {
    defineLexxy()
    defineTrix()
  }
  return mount(html, opts)
}

const EDITORS = `
  <input type="text" name="draft[title]">
  <lexxy-editor name="draft[body]"></lexxy-editor>
  <input type="hidden" name="draft[notes]" id="notes_trix_input" value="">
  <trix-editor input="notes_trix_input"></trix-editor>
  <trix-editor name="draft[aside]"></trix-editor>
  <div contenteditable="true" name="draft[summary]"></div>
  <div contenteditable="true">unnamed inner editable</div>
  <lexxy-editor name="draft[private]" data-reactive-persist="off"></lexxy-editor>
  <div data-controller="reactive" id="nested"><lexxy-editor name="inner_body"></lexxy-editor></div>
`

test("the snapshot includes named editors under their resolved names, never the paired hidden input", () => {
  const { controller, q } = mountEditors(EDITORS)
  controller.connect()
  q("lexxy-editor[name='draft[body]']").value = "<p>Essay</p>"
  q("trix-editor[input]").value = "<div>Notes</div>"
  q("trix-editor[name='draft[aside]']").value = "<div>Aside</div>"
  q("[name='draft[summary]']").textContent = "Plain summary"
  q("[name='draft[private]']").value = "<p>secret</p>"
  fire(q("[name='draft[title]']"), "change")
  expect(storage.json(KEY).fields).toEqual({
    "draft[title]": "",
    "draft[body]": "<p>Essay</p>",
    "draft[notes]": "<div>Notes</div>",
    "draft[aside]": "<div>Aside</div>",
    "draft[summary]": "Plain summary",
  })
})

test("an editor's own chrome (toolbar selects/inputs inside lexxy-editor, a trix-toolbar) is never a control", () => {
  const html = EDITORS.replace(
    '<lexxy-editor name="draft[body]"></lexxy-editor>',
    `<lexxy-editor name="draft[body]">
       <div class="lexxy-editor__content" contenteditable="true"><p>typed</p></div>
       <lexxy-toolbar><select name="lexxy-code-language"><option value="plain" selected>plain</option></select>
         <input type="url" name="href" value=""></lexxy-toolbar>
     </lexxy-editor>`,
  ).replace("<trix-editor", '<trix-toolbar><input type="url" name="href" value=""></trix-toolbar><trix-editor')
  seedDraft({ "lexxy-code-language": "ruby", href: "https://evil.example", "draft[body]": "<p>Draft</p>" })
  const { controller, q } = mountEditors(html)
  controller.connect()
  expect(q('[name="lexxy-code-language"]').value).toBe("plain")
  for (const input of el_all(q, '[name="href"]')) expect(input.value).toBe("")
  fire(q("[name='draft[title]']"), "change")
  const fields = storage.json(KEY).fields
  expect(fields).not.toHaveProperty("lexxy-code-language")
  expect(fields).not.toHaveProperty("href")
  expect(fields["draft[body]"]).toBe("<p>Draft</p>")
})

const el_all = (q, sel) => [...q(sel).ownerDocument.querySelectorAll(sel)]

test("restore replays through the editors' own value setters / textContent — never innerHTML", () => {
  seedDraft({
    "draft[body]": "<p>Essay</p>",
    "draft[notes]": "<div>Notes</div>",
    "draft[aside]": "<div>Aside</div>",
    "draft[summary]": "Plain <b>summary</b>",
  })
  const { controller, q } = mountEditors(EDITORS)
  controller.connect()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Essay</p>")
  expect(q("trix-editor[input]").value).toBe("<div>Notes</div>")
  expect(q("#notes_trix_input").value).toBe("<div>Notes</div>") // via loadHTML → the hidden input
  expect(q("trix-editor[name='draft[aside]']").value).toBe("<div>Aside</div>")
  expect(q("[name='draft[summary]']").textContent).toBe("Plain <b>summary</b>") // text, not markup
  expect(q("[name='draft[summary]']").querySelector("b")).toBeNull()
  expect(innerHTMLWrites).toBe(0)
  expect(storage.calls.set).toBe(0) // the editors' own change events are not `input`/`change`
})

test("restore: blank asks the editor — an empty-looking Lexxy value restores, a non-empty server body wins", () => {
  seedDraft({ "draft[body]": "<p>Draft</p>", "draft[notes]": "<div>Draft notes</div>", "draft[summary]": "Draft summary" })
  const html = EDITORS.replace(
    'id="notes_trix_input" value=""',
    'id="notes_trix_input" value="<div>Server notes</div>"',
  ).replace('name="draft[summary]">', 'name="draft[summary]">Server summary')
  const { controller, q } = mountEditors(html)
  // Lexxy's initial value is "<p><br></p>" — non-empty as a string, empty per isEmpty
  controller.connect()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Draft</p>")
  expect(q("trix-editor[input]").value).toBe("<div>Server notes</div>")
  expect(q("[name='draft[summary]']").textContent).toBe("Server summary")
})

test("restore: always lets the draft overwrite a server-rendered editor value", () => {
  seedDraft({ "draft[body]": "<p>Draft</p>", "draft[notes]": "<div>Draft notes</div>", "draft[summary]": "Draft summary" })
  const html = EDITORS.replace('name="draft[body]">', 'name="draft[body]" value="<p>Server</p>">')
    .replace('id="notes_trix_input" value=""', 'id="notes_trix_input" value="<div>Server notes</div>"')
    .replace('name="draft[summary]">', 'name="draft[summary]">Server summary')
  const { controller, q } = mountEditors(html, { payload: { ...PAYLOAD, restore: "always" } })
  controller.connect()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Draft</p>")
  expect(q("trix-editor[input]").value).toBe("<div>Draft notes</div>")
  expect(q("[name='draft[summary]']").textContent).toBe("Draft summary")
})

test("fields:, reactive_persist_skip and nested-root ownership apply to editors", () => {
  seedDraft({ "draft[body]": "<p>Draft</p>", "draft[private]": "<p>leak</p>", inner_body: "<p>leak</p>", "draft[summary]": "x" })
  const { controller, q } = mountEditors(EDITORS, { payload: { ...PAYLOAD, fields: ["draft[body]", "draft[private]"] } })
  controller.connect()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Draft</p>")
  expect(q("[name='draft[private]']").value).toBe("<p><br></p>")
  expect(q("[name='inner_body']").value).toBe("<p><br></p>")
  expect(q("[name='draft[summary]']").textContent).toBe("")
  q("[name='draft[summary]']").textContent = "typed"
  fire(q("[name='draft[title]']"), "change")
  expect(storage.json(KEY).fields).toEqual({ "draft[body]": "<p>Draft</p>" })
})

test("an editor that has not upgraded yet is omitted from the snapshot and restored once it is defined", async () => {
  seedDraft({ "draft[body]": "<p>Draft</p>", "draft[notes]": "<div>Draft notes</div>", "draft[title]": "T" })
  const { controller, q } = mountEditors(EDITORS, { late: true })
  controller.connect()
  expect(q("[name='draft[title]']").value).toBe("T")
  fire(q("[name='draft[title]']"), "change")
  expect(storage.json(KEY).fields).not.toHaveProperty("draft[body]")
  expect(storage.json(KEY).fields).not.toHaveProperty("draft[notes]")
  defineLexxy()
  defineTrix()
  await settle()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Draft</p>")
  expect(q("trix-editor[input]").value).toBe("<div>Draft notes</div>")
})

test("a deferred restore still honours restore: blank and skips a root that left the document", async () => {
  seedDraft({ "draft[body]": "<p>Draft</p>", "draft[extra]": "<p>Draft extra</p>", "draft[aside]": "<div>Draft aside</div>" })
  const html = EDITORS.replace('name="draft[body]">', 'name="draft[body]" value="<p>Server</p>">').replace(
    "<trix-editor",
    '<lexxy-editor name="draft[extra]"></lexxy-editor><trix-editor',
  )
  const { controller, q, el } = mountEditors(html, { late: true })
  controller.connect()
  defineLexxy()
  await settle()
  expect(q("lexxy-editor[name='draft[body]']").value).toBe("<p>Server</p>") // blank re-checked at apply time
  expect(q("lexxy-editor[name='draft[extra]']").value).toBe("<p>Draft extra</p>")
  expect(editorSets).toBe(1)
  el.remove()
  defineTrix()
  await settle()
  expect(editorSets).toBe(1) // the root left the document: no Trix apply
})

test("an editor's own change event schedules the draft write (Lexical and Trix don't bubble a native input)", () => {
  const { controller, q } = mountEditors(EDITORS)
  controller.connect()
  q("lexxy-editor[name='draft[body]']").value = "<p>Typed</p>" // the stub dispatches lexxy:change
  expect(timers.length).toBe(1) // the same trailing-edge debounce as `input`
  drainTimers()
  expect(storage.json(KEY).fields["draft[body]"]).toBe("<p>Typed</p>")
  q("trix-editor[input]").value = "<div>Typed notes</div>" // dispatches trix-change
  drainTimers()
  expect(storage.json(KEY).fields["draft[notes]"]).toBe("<div>Typed notes</div>")
  controller.disconnect()
  q("lexxy-editor[name='draft[body]']").value = "<p>After</p>"
  expect(timers.length).toBe(0) // listeners dropped on disconnect
})

test("a throwing editor setter never throws out of connect and is reported once under debug only", () => {
  seedDraft({ "draft[body]": "<p>Draft</p>" })
  const { controller, q } = mountEditors(EDITORS, { rootAttrs: 'data-reactive-debug="true"' })
  Object.defineProperty(q("lexxy-editor[name='draft[body]']"), "editor", { get: () => undefined })
  expect(() => controller.connect()).not.toThrow()
  expect(infos.length).toBe(1)
  expect(infos[0]).toContain("reactive_persist")
  expect(infos[0]).toContain("draft[body]")
})

test("without debug a throwing editor setter is silent", () => {
  seedDraft({ "draft[body]": "<p>Draft</p>" })
  const { controller, q } = mountEditors(EDITORS)
  Object.defineProperty(q("lexxy-editor[name='draft[body]']"), "editor", { get: () => undefined })
  expect(() => controller.connect()).not.toThrow()
  expect(infos).toEqual([])
})
