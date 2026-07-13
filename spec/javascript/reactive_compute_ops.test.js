// Unit tests for the issue #226 reserved reducer output `$ops` and the client
// `ops` builder exported from phlex/reactive/compute.
//
// A reducer may return the reserved key `$ops` holding an op chain (the `ops`
// builder or a raw [[name, args], ...] array). The controller consumes it as a
// PHASE 4 of the #183 single-pass write set — after the field writes, text
// sinks, and phase-3 input dispatches settle — through the same frozen
// CLIENT_OPS whitelist runOps uses. RISING-EDGE semantics: the chain runs only
// on the transition from "absent/null last pass" to "present this pass", and
// only on EVENT-DRIVEN passes — the connect/morph seed pass (no event) ARMS
// but never fires (that is what breaks the submit → error re-render → re-seed
// → submit loop). A later pass returning no $ops re-arms.
//
// Run with: bun test spec/javascript
import { test, expect, mock, beforeAll, beforeEach } from "bun:test"

let ReactiveController
let computeModule

beforeAll(async () => {
  mock.module("@hotwired/stimulus", () => ({
    Controller: class {
      constructor() {}
    },
  }))
  ReactiveController = (await import("../../app/javascript/phlex/reactive/reactive_controller.js")).default
  computeModule = await import("../../app/javascript/phlex/reactive/compute.js")
})

beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

// Same fake control as reactive_compute.test.js: programmatic .value writes
// coerce to String and fire NOTHING; dispatchEvent runs registered listeners.
function makeField(name, value) {
  const listeners = []
  return {
    name,
    tagName: "INPUT",
    _root: null,
    _value: String(value),
    get value() {
      return this._value
    },
    set value(v) {
      this._value = String(v)
    },
    closest() {
      return this._root
    },
    addEventListener: (type, fn) => type === "input" && listeners.push(fn),
    dispatchEvent(event) {
      Object.defineProperty(event, "target", { value: this, configurable: true })
      if (event.type === "input") listeners.slice().forEach((fn) => fn(event))
      return true
    },
  }
}

// A compute root that ALSO records dispatched events (for the dispatch op) and
// resolves closest("form") to an optional surrounding form (for the submit op).
function makeRoot({ reducer, inputs, outputs, fields, form = null }) {
  const attrs = {
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  const root = {
    id: "otp",
    dispatched: [],
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      const m = sel.match(/\[name="(.+?)"\]/)
      if (!m) return []
      const f = fields[m[1]]
      return f ? [f] : []
    },
    closest: (sel) => (sel === "form" ? form : null),
    dispatchEvent(event) {
      root.dispatched.push(event)
      return true
    },
  }
  for (const f of Object.values(fields)) f._root = root
  return root
}

function makeForm() {
  return {
    tagName: "FORM",
    submitted: 0,
    requestSubmit() {
      this.submitted += 1
    },
  }
}

// No CustomEvent stub: bun's native CustomEvent carries type/detail, which is
// all these tests read — and a bare recorder class left on globalThis would
// break every later file whose events need cancelable/preventDefault (bun runs
// the whole suite in ONE process; the CI-order lifecycle failure proved it).
function buildController(root) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.window ??= {}
  return controller
}

function captureWarnings(fn) {
  const warns = []
  const original = console.warn
  console.warn = (...args) => warns.push(args.join(" "))
  try {
    fn()
  } finally {
    console.warn = original
  }
  return warns
}

// --- the ops builder ---------------------------------------------------------

test("ops is an immutable chain: every verb returns a NEW instance", () => {
  const { ops } = computeModule
  const chained = ops.submit()

  expect(chained).not.toBe(ops)
  expect(ops.ops.length).toBe(0) // the shared starting point is untouched
  expect(chained.ops.length).toBe(1)
})

test("ops payloads are frozen ALL the way down (nested classes/transition arrays)", () => {
  const { ops } = computeModule
  const chain = ops
    .add_class(".x", ["a", "b"])
    .show("#y", { transition: { during: "t", from: "f", to: "to" } })

  expect(Object.isFrozen(chain.ops)).toBe(true)
  expect(Object.isFrozen(chain.ops[0])).toBe(true)
  expect(Object.isFrozen(chain.ops[0][1])).toBe(true)
  expect(Object.isFrozen(chain.ops[0][1].classes)).toBe(true)
  expect(Object.isFrozen(chain.ops[1][1].transition)).toBe(true)
  // A chain held in a constant can never be mutated by later use.
  expect(() => chain.ops[0][1].classes.push("evil")).toThrow()
})

test("ops verbs mirror the Ruby wire: dispatch defaults + submit default root", () => {
  const { ops } = computeModule
  const chain = ops.dispatch("code:complete", { detail: { digits: 6 } }).submit()

  expect(chain.ops).toEqual([
    ["dispatch", { name: "code:complete", to: "@root", detail: { digits: 6 } }],
    ["submit", { to: "@root" }],
  ])
})

test("ops covers the visibility/class/attr/text/focus vocabulary", () => {
  const { ops } = computeModule
  const chain = ops
    .show("#done")
    .hide("#hint", { global: true })
    .add_class(".status", "ok")
    .set_attr("#code", "aria-invalid", false)
    .text("#count", 6)
    .focus("#next")

  expect(chain.ops).toEqual([
    ["show", { to: "#done" }],
    ["hide", { to: "#hint", global: true }],
    ["add_class", { to: ".status", classes: ["ok"] }],
    ["set_attr", { to: "#code", name: "aria-invalid", value: "false" }],
    ["text", { to: "#count", value: "6" }],
    ["focus", { to: "#next" }],
  ])
})

test("ops serializes as the raw op list (toJSON), matching the wire format", () => {
  const { ops } = computeModule
  expect(JSON.stringify(ops.submit())).toBe('[["submit",{"to":"@root"}]]')
})

// --- $ops: rising edge, event-gated ------------------------------------------

function otpController({ complete, form = null, chain = null }) {
  const fields = { code: makeField("code", "") }
  computeModule.setComputeReducer("otp", ({ code }) => {
    const digits = code.replace(/\D/g, "").slice(0, 6)
    return {
      code: digits,
      $ops: complete(digits) ? (chain ?? computeModule.ops.dispatch("code:complete")) : null,
    }
  })
  const root = makeRoot({
    reducer: "otp",
    inputs: { code: "string" },
    outputs: ["code"],
    fields,
    form,
  })
  return { controller: buildController(root), fields, root }
}

const sixDigits = (digits) => digits.length === 6

test("$ops fires on the rising edge of an event-driven pass", () => {
  const { controller, fields, root } = otpController({ complete: sixDigits })

  fields.code.value = "123-456"
  controller.recompute({ target: fields.code })

  expect(fields.code.value).toBe("123456") // the write set still applied
  expect(root.dispatched.map((e) => e.type)).toEqual(["code:complete"])
})

test("$ops does NOT re-fire while the condition holds (no per-keystroke storm)", () => {
  const { controller, fields, root } = otpController({ complete: sixDigits })

  fields.code.value = "123456"
  controller.recompute({ target: fields.code })
  fields.code.value = "1234567" // capped back to 6 by the reducer — still complete
  controller.recompute({ target: fields.code })

  expect(root.dispatched.length).toBe(1)
})

test("a CHANGED $ops chain fires again — per-keystroke focus advance works", () => {
  // The multi-box OTP shape: each digit emits a DIFFERENT focus target. The
  // latch is keyed on chain CONTENT, so a new target is a new intent and
  // fires, while an identical chain (the submit case above) stays settled.
  const fields = { code: makeField("code", "") }
  computeModule.setComputeReducer("otp", ({ code }) => ({
    code,
    $ops: code.length > 0 ? [["dispatch", { name: `focus:d${code.length + 1}` }]] : null,
  }))
  const root = makeRoot({ reducer: "otp", inputs: { code: "string" }, outputs: ["code"], fields })
  const controller = buildController(root)

  fields.code.value = "1"
  controller.recompute({ target: fields.code })
  fields.code.value = "12"
  controller.recompute({ target: fields.code })
  fields.code.value = "12" // unchanged pass — same chain, no re-fire
  controller.recompute({ target: fields.code })

  expect(root.dispatched.map((e) => e.type)).toEqual(["focus:d2", "focus:d3"])
})

test("$ops re-arms when a pass returns no ops, then fires again", () => {
  const { controller, fields, root } = otpController({ complete: sixDigits })

  fields.code.value = "123456"
  controller.recompute({ target: fields.code })
  fields.code.value = "12345" // incomplete — re-arms
  controller.recompute({ target: fields.code })
  fields.code.value = "123456"
  controller.recompute({ target: fields.code })

  expect(root.dispatched.length).toBe(2)
})

test("a seed pass (no event) ARMS but never fires — and stays armed", () => {
  const { controller, fields, root } = otpController({ complete: sixDigits })

  fields.code.value = "123456" // restored/prefilled complete value
  controller.recompute() // the #199 connect/morph seed — no event

  expect(root.dispatched.length).toBe(0)

  // A later event-driven pass with the condition STILL true must not fire
  // either — no rising edge happened.
  controller.recompute({ target: fields.code })
  expect(root.dispatched.length).toBe(0)

  // Only after the condition breaks and returns does it fire.
  fields.code.value = "12345"
  controller.recompute({ target: fields.code })
  fields.code.value = "123456"
  controller.recompute({ target: fields.code })
  expect(root.dispatched.length).toBe(1)
})

// --- $ops: accepted shapes + isolation from the write set --------------------

test("$ops accepts a raw [[name, args]] array and defaults a missing to: to the root", () => {
  const form = makeForm()
  const { controller, fields } = otpController({
    complete: sixDigits,
    form,
    chain: [["submit", {}]], // raw array, no to: — resolves to @root → closest form
  })

  fields.code.value = "987654"
  controller.recompute({ target: fields.code })

  expect(form.submitted).toBe(1)
})

test("$ops is consumed — never written as a field even when declared in outputs:", () => {
  const fields = { code: makeField("code", ""), $ops: makeField("$ops", "untouched") }
  computeModule.setComputeReducer("otp", () => ({ code: "123456", $ops: [["dispatch", { name: "x" }]] }))
  const root = makeRoot({
    reducer: "otp",
    inputs: { code: "string" },
    outputs: ["code", "$ops"], // hostile/buggy declaration
    fields,
  })
  const controller = buildController(root)

  controller.recompute({ target: fields.code })

  expect(fields.$ops.value).toBe("untouched")
  expect(fields.code.value).toBe("123456")
})

test("an unknown op inside $ops warn-skips while siblings still apply", () => {
  const form = makeForm()
  const { controller, fields, root } = otpController({
    complete: sixDigits,
    form,
    chain: [
      ["evil_op", { to: "@root" }],
      ["submit", {}],
    ],
  })

  fields.code.value = "123456"
  const warns = captureWarnings(() => controller.recompute({ target: fields.code }))

  expect(warns.some((w) => w.includes("unknown client op"))).toBe(true)
  expect(form.submitted).toBe(1)
  expect(root.dispatched.length).toBe(0)
})

test("a non-chain, non-array $ops value warns and is skipped (default-deny)", () => {
  const { controller, fields, root } = otpController({ complete: sixDigits, chain: "submit" })

  fields.code.value = "123456"
  const warns = captureWarnings(() => controller.recompute({ target: fields.code }))

  expect(warns.some((w) => w.includes("$ops"))).toBe(true)
  expect(root.dispatched.length).toBe(0)
})

// --- $ops ordering: after the write set settles -------------------------------

test("$ops runs AFTER the phase-3 input dispatches (chained listeners see settled values)", () => {
  const order = []
  const fields = { code: makeField("code", "12345"), echo: makeField("echo", "") }
  fields.echo.addEventListener("input", () => order.push("chained-input"))
  computeModule.setComputeReducer("otp", ({ code }) => ({
    echo: code,
    $ops: code.length === 6 ? [["dispatch", { name: "done" }]] : null,
  }))
  const root = makeRoot({
    reducer: "otp",
    inputs: { code: "string" },
    outputs: ["echo"],
    fields,
  })
  const realDispatch = root.dispatchEvent
  root.dispatchEvent = (event) => {
    order.push("ops")
    return realDispatch(event)
  }
  const controller = buildController(root)

  fields.code.value = "123456"
  controller.recompute({ target: fields.code })

  expect(order).toEqual(["chained-input", "ops"])
})
