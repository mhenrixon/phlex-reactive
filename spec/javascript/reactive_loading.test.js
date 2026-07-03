// Unit tests for declarative loading states on reactive triggers (issue #99).
//
// `on(:x, loading: { … })` / `on(:x, disable_with: "…")` emit
// data-reactive-loading-param (JSON) that Stimulus surfaces as
// event.params.loading. The controller, when a request is ENQUEUED (covering the
// queue wait, not just the fetch):
//
//   * marks the TRIGGER with data-reactive-busy="<action>" and the root with the
//     SAME action token in a SPACE-SEPARATED set (two queued actions never
//     clobber), plus aria-busy via a PENDING COUNTER (removed only at zero),
//   * applies the loading class, disables the trigger, swaps its text — but the
//     disable + text swap happen at ENQUEUE, never during a debounce quiet
//     period (a debounced input's element must not be disabled mid-typing),
//   * scopes busy_on elements: data-reactive-busy-on="save" gets
//     data-reactive-busy toggled only while `save` is in flight,
//   * on settle (success OR failure) restores the trigger, GUARDED — skipped if
//     the trigger disconnected, and the text is not clobbered if a morph rendered
//     a new server label (textContent no longer equals the disable_with text).
//
// The trigger is event.currentTarget (a <button><span> click's target is the
// span, which carries no params) — captured in dispatch and threaded through.
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

// A fake element with a classList over a Set, a token-store for attributes, a
// `disabled` flag, and `textContent`. `isConnected` defaults true. Records
// blur/input listeners so a debounce flush can be driven.
function makeEl({ owner = null } = {}) {
  const listeners = {}
  const attrs = {}
  const el = {
    isConnected: true,
    disabled: false,
    textContent: "",
    classes: new Set(),
    closest: () => owner,
    getAttribute: (n) => (n in attrs ? attrs[n] : null),
    setAttribute: (n, v) => {
      attrs[n] = String(v)
    },
    removeAttribute: (n) => {
      delete attrs[n]
    },
    hasAttribute: (n) => n in attrs,
    addEventListener: (t, fn) => {
      (listeners[t] ||= []).push(fn)
    },
    removeEventListener: (t, fn) => {
      listeners[t] = (listeners[t] || []).filter((f) => f !== fn)
    },
    fire: (t) => (listeners[t] || []).slice().forEach((fn) => fn()),
  }
  el.classList = {
    add: (...cs) => cs.forEach((c) => el.classes.add(c)),
    remove: (...cs) => cs.forEach((c) => el.classes.delete(c)),
    toggle: (c) => (el.classes.has(c) ? el.classes.delete(c) : el.classes.add(c)),
    contains: (c) => el.classes.has(c),
  }
  return el
}

let root

// A reactive root that resolves `to:`/busy_on selectors from a `matches` map,
// tracks its own attributes (aria-busy, data-reactive-busy set), and owns the
// trigger. querySelectorAll returns whatever the map holds for a selector.
function makeRoot(matches = {}) {
  const attrs = {}
  return {
    isConnected: true,
    id: "counter",
    hidden: false,
    getAttribute: (n) => (n in attrs ? attrs[n] : null),
    setAttribute: (n, v) => {
      attrs[n] = String(v)
    },
    removeAttribute: (n) => {
      delete attrs[n]
    },
    hasAttribute: (n) => n in attrs,
    dispatchEvent: () => {},
    contains: () => false,
    querySelectorAll: (sel) => matches[sel] ?? [],
  }
}

// Build a controller with a scripted fetch. `responses` is consumed in order;
// the last repeats. Each is {...response fields} or { reject: Error }. A
// `hold` promise lets a test keep the fetch pending to inspect mid-flight state.
function buildController(responses, { rootMatches = {}, hold = null } = {}) {
  root = makeRoot(rootMatches)
  const controller = new ReactiveController()
  controller.element = root
  controller.tokenValue = "tok"
  let calls = 0
  globalThis.fetch = async () => {
    const script = responses[Math.min(calls, responses.length - 1)]
    calls++
    if (hold) await hold
    if (script.reject) return Promise.reject(script.reject)
    return {
      redirected: script.redirected ?? false,
      ok: script.ok ?? true,
      status: script.status ?? 200,
      headers: { get: () => script.contentType ?? "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(script.body ?? ""),
    }
  }
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }
  return { controller, calls: () => calls }
}

// Fire a dispatch with a loading hint. `trigger` is event.currentTarget.
function fireDispatch(controller, trigger, loading, extra = {}) {
  const event = {
    target: trigger,
    currentTarget: trigger,
    params: { action: "save", params: "{}", loading, ...extra },
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
  return { promise: controller.dispatch(event), event }
}

// --- currentTarget capture --------------------------------------------------

test("the trigger is event.currentTarget, not event.target (a nested span click)", async () => {
  const { controller } = buildController([{}])
  const button = makeEl()
  const span = makeEl() // the inner <span> the click actually landed on
  const event = {
    target: span, // the span carries no loading/params
    currentTarget: button, // on() is spread onto the button
    params: { action: "save", params: "{}", loading: { class: ["busy"] } },
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true
    },
  }
  controller.dispatch(event)
  // The class must land on the BUTTON (currentTarget), never the span.
  expect(button.classes.has("busy")).toBe(true)
  expect(span.classes.has("busy")).toBe(false)
  await controller.queue
})

// --- busy vocabulary at enqueue ---------------------------------------------

test("marks the trigger with data-reactive-busy=<action> on enqueue", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { disable: true })
  expect(trigger.getAttribute("data-reactive-busy")).toBe("save")
  await promise
})

test("adds the action token to the root's SPACE-SEPARATED busy set", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { disable: true })
  expect(root.getAttribute("data-reactive-busy")).toBe("save")
  await promise
})

test("sets aria-busy on the root during the pending window", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}], { hold })
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { disable: true })
  expect(root.getAttribute("aria-busy")).toBe("true")
  release()
  await promise
  expect(root.hasAttribute("aria-busy")).toBe(false)
})

test("applies the loading class + disable + text swap on enqueue", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}], { hold })
  const trigger = makeEl()
  trigger.textContent = "Save"

  const { promise } = fireDispatch(controller, trigger, { disable: true, class: ["opacity-50"], text: "Saving…" })
  expect(trigger.disabled).toBe(true)
  expect(trigger.classes.has("opacity-50")).toBe(true)
  expect(trigger.textContent).toBe("Saving…")
  release()
  await promise
})

test("a to: selector applies the loading class to owned matches, not the trigger", async () => {
  const spinner = makeEl()
  spinner.closest = () => root
  const { controller } = buildController([{}], { rootMatches: { ".spinner": [spinner] } })
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { class: ["on"], to: ".spinner" })
  expect(spinner.classes.has("on")).toBe(true)
  expect(trigger.classes.has("on")).toBe(false)
  await promise
})

// --- busy_on scoping --------------------------------------------------------

test("busy_on element gets data-reactive-busy while its action is in flight, cleared after", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const spinner = makeEl()
  spinner.closest = () => root
  spinner.setAttribute("data-reactive-busy-on", "save")
  const { controller } = buildController([{}], {
    hold,
    rootMatches: { "[data-reactive-busy-on]": [spinner] },
  })
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { disable: true })
  expect(spinner.getAttribute("data-reactive-busy")).toBe("save")
  release()
  await promise
  expect(spinner.hasAttribute("data-reactive-busy")).toBe(false)
})

test("busy_on element for a DIFFERENT action is not marked", async () => {
  const spinner = makeEl()
  spinner.closest = () => root
  spinner.setAttribute("data-reactive-busy-on", "destroy") // different action
  const { controller } = buildController([{}], {
    rootMatches: { "[data-reactive-busy-on]": [spinner] },
  })
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { disable: true })
  expect(spinner.hasAttribute("data-reactive-busy")).toBe(false)
  await promise
})

// --- restore on settle (success) --------------------------------------------

test("restores disabled + text on success settle", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()
  trigger.textContent = "Save"

  const { promise } = fireDispatch(controller, trigger, { disable: true, text: "Saving…" })
  await promise
  expect(trigger.disabled).toBe(false)
  expect(trigger.textContent).toBe("Save")
  expect(trigger.hasAttribute("data-reactive-busy")).toBe(false)
})

test("restores disabled + text on failure settle", async () => {
  const { controller } = buildController([{ ok: false, status: 500 }])
  const trigger = makeEl()
  trigger.textContent = "Save"
  const originalError = console.error
  console.error = () => {}
  try {
    const { promise } = fireDispatch(controller, trigger, { disable: true, text: "Saving…" })
    await promise
  } finally {
    console.error = originalError
  }
  expect(trigger.disabled).toBe(false)
  expect(trigger.textContent).toBe("Save")
})

test("removes the loading class on settle", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()

  const { promise } = fireDispatch(controller, trigger, { class: ["opacity-50"] })
  await promise
  expect(trigger.classes.has("opacity-50")).toBe(false)
})

// --- guarded restore --------------------------------------------------------

test("restore is SKIPPED when the trigger left the DOM (guarded by isConnected)", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()
  trigger.textContent = "Save"

  const { promise } = fireDispatch(controller, trigger, { disable: true, text: "Saving…" })
  trigger.isConnected = false // a plain replace detached the trigger
  await promise
  // No restore against a detached node — text stays as swapped (the node is gone).
  expect(trigger.textContent).toBe("Saving…")
})

test("does NOT clobber a server-rendered new label (textContent changed by the morph)", async () => {
  const { controller } = buildController([{}])
  const trigger = makeEl()
  trigger.textContent = "Save"

  const { promise } = fireDispatch(controller, trigger, { disable: true, text: "Saving…" })
  // A morph re-rendered the trigger with a fresh label before the settle lands.
  trigger.textContent = "Saved ✓"
  await promise
  // The restore must NOT overwrite the server's new label with the old "Save".
  expect(trigger.textContent).toBe("Saved ✓")
  // The disabled flag is still restored (it's the client's, not the server's).
  expect(trigger.disabled).toBe(false)
})

// --- pending counter across overlapping enqueues ----------------------------

test("aria-busy survives A's settle while B is still queued (pending counter)", async () => {
  // A per-call gate so we can release A's fetch while B's stays pending. The
  // queue serializes #perform, so only A is in flight when we release its gate;
  // B's #perform then starts and blocks on gate #2.
  const gates = []
  const nextGate = () => {
    let release
    const p = new Promise((r) => (release = r))
    gates.push(release)
    return p
  }
  root = makeRoot()
  const controller = new ReactiveController()
  controller.element = root
  controller.tokenValue = "tok"
  globalThis.fetch = async () => {
    await nextGate()
    return {
      redirected: false,
      ok: true,
      status: 200,
      headers: { get: () => "text/vnd.turbo-stream.html" },
      text: () => Promise.resolve(""),
    }
  }
  globalThis.document = { querySelector: () => null, dispatchEvent: () => {} }
  globalThis.window = { Turbo: { renderStreamMessage: () => {} } }

  const triggerA = makeEl()
  const triggerB = makeEl()

  // Enqueue A then B — both pending; counter = 2.
  fireDispatch(controller, triggerA, { disable: true }, { action: "a" })
  fireDispatch(controller, triggerB, { disable: true }, { action: "b" })
  await wait(5) // let A's #perform reach its fetch/gate
  expect(root.getAttribute("aria-busy")).toBe("true")

  // Release A's gate: A settles, but B is next in the serialized queue.
  gates[0]()
  await wait(5)
  // With A settled and B still in flight (or newly started), aria-busy must NOT
  // have been cleared — the pending counter is still > 0.
  expect(root.getAttribute("aria-busy")).toBe("true")

  await wait(5)
  gates[1]?.() // release B
  await controller.queue
  // Both settled → counter 0 → attribute removed.
  expect(root.hasAttribute("aria-busy")).toBe(false)
})

test("the root busy set keeps a token until ALL its requests settle (per-action refcount)", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}, {}], { hold })
  const t1 = makeEl()
  const t2 = makeEl()

  // Two "save" requests overlapping.
  fireDispatch(controller, t1, { disable: true })
  fireDispatch(controller, t2, { disable: true })
  expect(root.getAttribute("data-reactive-busy")).toBe("save")

  release()
  await controller.queue
  // Both settled → the token is gone.
  expect(root.hasAttribute("data-reactive-busy")).toBe(false)
})

test("two different queued actions keep both tokens in the space-separated set", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}, {}], { hold })
  const t1 = makeEl()
  const t2 = makeEl()

  fireDispatch(controller, t1, { disable: true }, { action: "save" })
  fireDispatch(controller, t2, { disable: true }, { action: "publish" })

  const set = root.getAttribute("data-reactive-busy").split(" ").sort()
  expect(set).toEqual(["publish", "save"])
  release()
  await controller.queue
})

// --- debounce: disable only at flush, not during the quiet period -----------

test("a debounced trigger is NOT disabled during the quiet period, only at flush", async () => {
  // Hold the fetch so the request stays pending after the flush — otherwise the
  // whole round trip completes within the wait and the busy state settles before
  // we can observe it.
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}], { hold })
  const input = makeEl()
  input.textContent = ""

  // Fire a debounced dispatch; the disable must NOT apply yet (still typing) —
  // the debounced input's element must not be disabled during the quiet period.
  fireDispatch(controller, input, { disable: true }, { debounce: 50 })
  expect(input.disabled).toBe(false)
  expect(input.hasAttribute("data-reactive-busy")).toBe(false)

  // Cross the quiet period → flush → enqueue → NOW the busy state applies.
  await wait(80)
  expect(input.disabled).toBe(true)
  expect(input.getAttribute("data-reactive-busy")).toBe("save")
  release()
  await controller.queue
})

// --- always-on busy vocabulary (no loading hint needed) ---------------------

test("the busy vocabulary is ALWAYS-ON — a bare on() (no loading hint) still marks busy", async () => {
  let release
  const hold = new Promise((r) => (release = r))
  const { controller } = buildController([{}], { hold })
  const trigger = makeEl()

  // No loading hint at all — the always-on data-reactive-busy/aria-busy vocab
  // still fires so an app styles a spinner with pure CSS and zero Ruby.
  const { promise } = fireDispatch(controller, trigger, undefined)
  expect(trigger.getAttribute("data-reactive-busy")).toBe("save")
  expect(root.getAttribute("data-reactive-busy")).toBe("save")
  expect(root.getAttribute("aria-busy")).toBe("true")
  // …but with no hint there is NO disable, NO class, NO text swap.
  expect(trigger.disabled).toBe(false)
  expect(trigger.classes.size).toBe(0)
  release()
  await promise
  // All busy markers clear on settle.
  expect(trigger.hasAttribute("data-reactive-busy")).toBe(false)
  expect(root.hasAttribute("data-reactive-busy")).toBe(false)
  expect(root.hasAttribute("aria-busy")).toBe(false)
})
