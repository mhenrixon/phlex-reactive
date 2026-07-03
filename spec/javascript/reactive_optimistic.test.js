// Unit tests for optimistic visual hints on reactive triggers (issue #98).
//
// `on(:x, optimistic: { … })` emits data-reactive-optimistic-param (JSON) that
// Stimulus surfaces as event.params.optimistic. The controller:
//
//   * applies the hint ONCE per FLUSHED enqueue (not per raw dispatch — a
//     debounced trigger must not flap toggle_class per keystroke),
//   * records the exact INVERSE ops on the queued request,
//   * on ANY failure branch (redirected/http/content-type/network + apply)
//     replays the inverse, guarded by element.isConnected,
//   * on success does NO cleanup — the morph overwrites the hint with server
//     truth, or (reply.remove / streams-only) the hint is LEFT standing.
//
// checked: :keep makes a CLICK-bound checkbox/radio trigger SKIP the
// unconditional preventDefault so the native flip happens now.
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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// A fake DOM element: hidden flag + classList over a Set. `closest` returns the
// nearest reactive root (`owner`) so the ownership guard resolves `to:` targets.
function makeEl({ owner = null } = {}) {
  const el = {
    hidden: false,
    classes: new Set(),
    closest: () => owner,
  }
  el.classList = {
    add: (...cs) => cs.forEach((c) => el.classes.add(c)),
    remove: (...cs) => cs.forEach((c) => el.classes.delete(c)),
    toggle: (c) => (el.classes.has(c) ? el.classes.delete(c) : el.classes.add(c)),
  }
  return el
}

// The trigger element the event fires on. A blur-recording target (debounce
// flush) plus optional type/checked (checkbox skip-preventDefault path). It is
// its own owner so a hint with no `to:` applies to it and it's an owned match.
function makeTrigger({ type = "button", checked = false } = {}) {
  const listeners = {}
  const el = makeEl()
  el.type = type
  el.checked = checked
  el.addEventListener = (t, fn) => {
    (listeners[t] ||= []).push(fn)
  }
  el.removeEventListener = (t, fn) => {
    listeners[t] = (listeners[t] || []).filter((f) => f !== fn)
  }
  el.fire = (t) => (listeners[t] || []).slice().forEach((fn) => fn())
  el.closest = () => root // set below once root exists
  return el
}

let root

// A reactive root that resolves `to:` selectors from a map and owns the trigger.
function makeRoot(matches = {}) {
  return {
    isConnected: true,
    id: "counter",
    hidden: false,
    getAttribute: () => null,
    setAttribute: () => {},
    removeAttribute: () => {},
    dispatchEvent: () => {},
    contains: () => false,
    querySelectorAll: (sel) => matches[sel] ?? [],
  }
}

// Build a controller with a scripted fetch. `responses` is consumed in order;
// the last repeats. Each is {...response fields} or { reject: Error }.
function buildController(responses, { rootMatches = {} } = {}) {
  root = makeRoot(rootMatches)
  const controller = new ReactiveController()
  controller.element = root
  controller.tokenValue = "tok"
  let calls = 0
  globalThis.fetch = () => {
    const script = responses[Math.min(calls, responses.length - 1)]
    calls++
    if (script.reject) return Promise.reject(script.reject)
    return Promise.resolve({
      redirected: script.redirected ?? false,
      ok: script.ok ?? true,
      status: script.status ?? 200,
      headers: { get: () => script.contentType ?? "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(script.body ?? ""),
    })
  }
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, calls: () => calls }
}

// Fire a dispatch with an optimistic hint. `trigger` is the event target.
function fireDispatch(controller, trigger, optimistic, extra = {}) {
  const event = {
    target: trigger,
    params: { action: "toggle", params: "{}", optimistic, ...extra },
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
  return { promise: controller.dispatch(event), event }
}

// --- apply-on-dispatch ------------------------------------------------------

test("add_class applies to the trigger immediately on dispatch (before the reply)", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  // Applied synchronously — before the fetch resolves.
  expect(trigger.classes.has("busy")).toBe(true)
  await promise
})

test("toggle_class toggles the trigger class on dispatch", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()
  trigger.classes.add("done")

  const { promise } = fireDispatch(controller, trigger, { toggle_class: ["done"] })
  expect(trigger.classes.has("done")).toBe(false) // toggled off
  await promise
})

test("hide: true hides the trigger on dispatch", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { hide: true })
  expect(trigger.hidden).toBe(true)
  await promise
})

test("a to: selector applies the hint to owned matches inside the root, not the trigger", async () => {
  const badge = makeEl({ owner: null })
  badge.closest = () => root
  const { controller } = buildController([{}], { rootMatches: { ".badge": [badge] } })
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["on"], to: ".badge" })
  expect(badge.classes.has("on")).toBe(true)
  expect(trigger.classes.has("on")).toBe(false) // NOT the trigger
  await promise
})

test("to: @root applies the hint to the root element itself", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { hide: true, to: "@root" })
  expect(root.hidden).toBe(true)
  await promise
})

// --- checked: :keep skips preventDefault ------------------------------------

test("checked: :keep on a CLICK-bound checkbox trigger SKIPS preventDefault (native flip)", () => {
  const { controller } = buildController([{}])
  const checkbox = makeTrigger({ type: "checkbox" })

  const { event } = fireDispatch(controller, checkbox, { checked: "keep" })
  // The native checkbox flip must be allowed — preventDefault NOT called.
  expect(event.defaultPrevented).toBe(false)
})

test("checked: :keep on a radio trigger also skips preventDefault", () => {
  const { controller } = buildController([{}])
  const radio = makeTrigger({ type: "radio" })

  const { event } = fireDispatch(controller, radio, { checked: "keep" })
  expect(event.defaultPrevented).toBe(false)
})

test("an element-bound NON-checkbox trigger still preventDefaults even with a hint", () => {
  const { controller } = buildController([{}])
  const button = makeTrigger({ type: "button" })

  const { event } = fireDispatch(controller, button, { add_class: ["busy"] })
  expect(event.defaultPrevented).toBe(true)
})

test("checked: :keep does NOT skip preventDefault for a non-checkbox element (a button)", () => {
  const { controller } = buildController([{}])
  const button = makeTrigger({ type: "button" })

  const { event } = fireDispatch(controller, button, { checked: "keep" })
  // A button has no native checkbox flip; the in-form submit default must still
  // be prevented.
  expect(event.defaultPrevented).toBe(true)
})

// --- revert on failure (each branch) ----------------------------------------

test("add_class reverts (removes the class) when the action fails HTTP", async () => {
  const { controller } = buildController([{ ok: false, status: 403 }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  expect(trigger.classes.has("busy")).toBe(true) // applied
  await promise
  expect(trigger.classes.has("busy")).toBe(false) // reverted on failure
})

test("remove_class reverts (re-adds the class) on failure", async () => {
  const { controller } = buildController([{ ok: false, status: 500 }])
  const trigger = makeTrigger()
  trigger.classes.add("active")

  const { promise } = fireDispatch(controller, trigger, { remove_class: ["active"] })
  expect(trigger.classes.has("active")).toBe(false) // applied
  await promise
  expect(trigger.classes.has("active")).toBe(true) // reverted
})

test("toggle_class reverts (toggles back) on failure", async () => {
  const { controller } = buildController([{ ok: false, status: 500 }])
  const trigger = makeTrigger()
  trigger.classes.add("done")

  const { promise } = fireDispatch(controller, trigger, { toggle_class: ["done"] })
  expect(trigger.classes.has("done")).toBe(false) // toggled off
  await promise
  expect(trigger.classes.has("done")).toBe(true) // toggled back on failure
})

test("hide reverts (shows again) on failure", async () => {
  const { controller } = buildController([{ ok: false, status: 500 }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { hide: true })
  expect(trigger.hidden).toBe(true)
  await promise
  expect(trigger.hidden).toBe(false) // shown again on failure
})

test("revert fires from the REDIRECTED branch", async () => {
  const { controller } = buildController([{ redirected: true, status: 200 }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  await promise
  expect(trigger.classes.has("busy")).toBe(false)
})

test("revert fires from the CONTENT-TYPE branch", async () => {
  const { controller } = buildController([{ contentType: "text/html" }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  await promise
  expect(trigger.classes.has("busy")).toBe(false)
})

test("revert fires from the NETWORK branch", async () => {
  const { controller } = buildController([{ reject: new Error("offline") }])
  const trigger = makeTrigger()
  const originalError = console.error
  console.error = () => {}
  try {
    const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
    await promise
  } finally {
    console.error = originalError
  }
  expect(trigger.classes.has("busy")).toBe(false)
})

test("revert fires from the APPLY branch (Turbo.renderStreamMessage throws)", async () => {
  const html = '<turbo-stream action="replace" target="counter"><template></template></turbo-stream>'
  const { controller } = buildController([{ body: html }])
  const trigger = makeTrigger()
  globalThis.window.Turbo.renderStreamMessage = () => {
    throw new Error("Turbo choked")
  }
  const originalError = console.error
  console.error = () => {}
  try {
    const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
    await promise
  } finally {
    console.error = originalError
    globalThis.window.Turbo.renderStreamMessage = () => {}
  }
  expect(trigger.classes.has("busy")).toBe(false)
})

// --- revert skipped when disconnected ---------------------------------------

test("revert is SKIPPED when the root left the DOM (guarded by isConnected)", async () => {
  const { controller } = buildController([{ ok: false, status: 500 }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  root.isConnected = false // a plain replace detached the subtree before the failure
  await promise
  // No revert attempted against a detached tree — the class stays as applied
  // (the node is gone anyway; the point is we don't touch a stale element).
  expect(trigger.classes.has("busy")).toBe(true)
})

// --- once per flush (debounce) ----------------------------------------------

test("a debounced trigger applies the hint ONCE per flush, not per keystroke", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()
  let toggles = 0
  const realToggle = trigger.classList.toggle
  trigger.classList.toggle = (c) => {
    toggles++
    return realToggle(c)
  }

  // Five rapid dispatches inside one debounce window.
  for (let i = 0; i < 5; i++) {
    fireDispatch(controller, trigger, { toggle_class: ["typing"] }, { debounce: 50 })
    await wait(5)
  }
  // Nothing applied yet — the hint waits for the flush, so it can't flap per key.
  expect(toggles).toBe(0)

  await wait(80) // cross the quiet period → one flush → one apply
  expect(toggles).toBe(1)
  await controller.queue
})

// --- success leaves no revert artifacts -------------------------------------

test("on success the hint is LEFT standing (no cleanup, no revert)", async () => {
  const html = '<turbo-stream action="replace" target="counter"><template></template></turbo-stream>'
  const { controller } = buildController([{ body: html }])
  const trigger = makeTrigger()

  const { promise } = fireDispatch(controller, trigger, { add_class: ["busy"] })
  await promise
  // No revert on success — the server morph (or reply.remove) owns the truth.
  expect(trigger.classes.has("busy")).toBe(true)
})

// --- no hint → untouched fast path ------------------------------------------

test("no optimistic hint → dispatch behaves exactly as before (still preventDefaults, no ops)", async () => {
  const { controller } = buildController([{}])
  const trigger = makeTrigger()

  const { event, promise } = fireDispatch(controller, trigger, undefined)
  expect(event.defaultPrevented).toBe(true)
  expect(trigger.classes.size).toBe(0)
  await promise
})
