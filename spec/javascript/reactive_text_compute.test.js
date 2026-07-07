// Unit tests for issue #104: typed compute inputs + reactive_text mirrors.
//
// Two additions to the client-side compute (#recompute):
//
//   1. TYPED INPUTS. The inputs param can be a JSON OBJECT { name: type } (hash
//      form) instead of a JSON ARRAY of names (array form). A :number input is
//      coerced through Number (the shipped behavior — blank/NaN → 0); a :string
//      input is read raw (field.value ?? ""). The array form stays numeric.
//
//   2. TEXT-NODE OUTPUTS + IDENTITY MIRRORS. An output whose name has no owned
//      form field is written to every owned [data-reactive-text="<name>"] node
//      via textContent (change-guarded, XSS-safe, no input dispatch — a text
//      node has no listeners). A separate ALWAYS-RUN pass mirrors each declared
//      INPUT's raw string value into its owned text nodes, so reactive_text(:x)
//      works with NO registered reducer.
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

// A named form control (REAL DOM semantics): a programmatic .value write coerces
// to String and fires NOTHING; listeners run only via dispatchEvent. `closest`
// resolves to the owning root so #ownsField (issue #15) treats it as owned.
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
    getAttribute() {
      return null
    },
    addEventListener: (type, fn) => type === "input" && listeners.push(fn),
    dispatchEvent(event) {
      Object.defineProperty(event, "target", { value: this, configurable: true })
      if (event.type === "input") listeners.slice().forEach((fn) => fn(event))
      return true
    },
  }
}

// A [data-reactive-text="<name>"] mirror node: only textContent (no `value`, no
// `name`), `closest` resolves ownership. It carries NO listeners — writing a
// text node never dispatches input (nothing would hear it).
function makeTextNode(name, text = "") {
  return {
    _root: null,
    _mirror: name,
    textContent: text,
    closest() {
      return this._root
    },
    getAttribute(attr) {
      return attr === "data-reactive-text" ? this._mirror : null
    },
  }
}

// A root that resolves BOTH named fields ([name="x"]) and text mirrors
// ([data-reactive-text="x"]) from a flat registry, mirroring how the real DOM's
// querySelectorAll would return each. `inputs` may be an array (array form) or
// an object (hash form) — serialized verbatim to the inputs param.
function makeRoot({ reducer, inputs, outputs, fields = {}, texts = {}, scope = null }) {
  const attrs = {
    "data-reactive-compute-reducer-param": reducer,
    "data-reactive-compute-inputs-param": JSON.stringify(inputs),
    "data-reactive-compute-outputs-param": JSON.stringify(outputs),
  }
  if (scope) attrs["data-reactive-scope"] = scope
  const root = {
    id: "preview",
    getAttribute: (k) => attrs[k] ?? null,
    querySelectorAll: (sel) => {
      let m = sel.match(/\[name="(.+?)"\]/)
      if (m) {
        const f = fields[m[1]]
        return f ? [f] : []
      }
      m = sel.match(/\[data-reactive-text="(.+?)"\]/)
      if (m) {
        const nodes = texts[m[1]]
        return nodes ? (Array.isArray(nodes) ? nodes : [nodes]) : []
      }
      return []
    },
    closest: () => null,
  }
  for (const f of Object.values(fields)) f._root = root
  for (const list of Object.values(texts)) {
    for (const n of Array.isArray(list) ? list : [list]) n._root = root
  }
  return root
}

function buildController(root) {
  const controller = new ReactiveController()
  controller.element = root
  globalThis.window ??= {}
  return controller
}

beforeEach(() => {
  computeModule.__resetComputeRegistryForTest()
})

// ---------------------------------------------------------------------------
// Typed inputs: string vs number coercion matrix.
// ---------------------------------------------------------------------------

test("a :string input is passed to the reducer RAW (not coerced through Number)", () => {
  const fields = { title: makeField("title", "Hi there") }
  let seen
  computeModule.setComputeReducer("preview", (values) => {
    seen = values
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "preview", inputs: { title: "string" }, outputs: [], fields }),
  )
  controller.recompute({ target: fields.title })

  // Raw string — Number("Hi there") would have been NaN→0 under the old path.
  expect(seen).toEqual({ title: "Hi there" })
})

test("a blank :string input is passed as '' (not 0)", () => {
  const fields = { title: makeField("title", "") }
  let seen
  computeModule.setComputeReducer("preview", (values) => {
    seen = values
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "preview", inputs: { title: "string" }, outputs: [], fields }),
  )
  controller.recompute({ target: fields.title })
  expect(seen).toEqual({ title: "" })
})

test("a :number input is coerced through Number (blank → 0), alongside a :string", () => {
  const fields = { title: makeField("title", "Hello"), qty: makeField("qty", "") }
  let seen
  computeModule.setComputeReducer("preview", (values) => {
    seen = values
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "preview", inputs: { title: "string", qty: "number" }, outputs: [], fields }),
  )
  controller.recompute({ target: fields.qty })

  expect(seen).toEqual({ title: "Hello", qty: 0 })
})

test("the ARRAY input form still coerces every input through Number (backward compatible)", () => {
  const fields = { allowance: makeField("allowance", "100"), total: makeField("total", "500") }
  let seen
  computeModule.setComputeReducer("split", (values) => {
    seen = values
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "split", inputs: ["allowance", "total"], outputs: [], fields }),
  )
  controller.recompute({ target: fields.allowance })

  expect(seen).toEqual({ allowance: 100, total: 500 })
})

test("meta.changed still reports the edited typed input by name", () => {
  const fields = { title: makeField("title", "Hi"), qty: makeField("qty", "3") }
  let meta
  computeModule.setComputeReducer("preview", (_values, m) => {
    meta = m
    return {}
  })

  const controller = buildController(
    makeRoot({ reducer: "preview", inputs: { title: "string", qty: "number" }, outputs: [], fields }),
  )
  controller.recompute({ target: fields.title })
  expect(meta).toEqual({ changed: "title" })
})

// ---------------------------------------------------------------------------
// Text-node outputs + output→field precedence.
// ---------------------------------------------------------------------------

test("an output with no owned field writes to its [data-reactive-text] node via textContent", () => {
  const fields = { title: makeField("title", "Hi") }
  const preview = makeTextNode("title_preview", "")
  computeModule.setComputeReducer("preview", ({ title }) => ({ title_preview: title }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { title: "string" },
      outputs: ["title_preview"],
      fields,
      texts: { title_preview: preview },
    }),
  )
  controller.recompute({ target: fields.title })

  expect(preview.textContent).toBe("Hi")
})

test("a result key paints BOTH a same-named field and text node (issue #183 — sinks declare themselves)", () => {
  const field = makeField("shared", "old")
  const text = makeTextNode("shared", "old")
  computeModule.setComputeReducer("preview", () => ({ shared: "new" }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { seed: "string" },
      outputs: ["shared"],
      fields: { seed: makeField("seed", "x"), shared: field },
      texts: { shared: text },
    }),
  )
  controller.recompute({ target: controller.element.querySelectorAll('[name="seed"]')[0] })

  // Issue #183: every result key paints into ANY matching sink — the field (it is
  // in outputs:) AND the text node (by presence). The old field-XOR-text rule is
  // gone; a text node no longer needs to be smuggled into outputs: to receive a value.
  expect(field.value).toBe("new")
  expect(text.textContent).toBe("new")
})

test("a text-node sink NOT in outputs: still paints (issue #183 — no smuggling into outputs:)", () => {
  const text = makeTextNode("greeting", "old")
  // The reducer returns `greeting`, but it is NOT declared in outputs: — under the
  // old rule it would never reach the text node. Issue #183: sinks declare
  // themselves, so a matching reactive_text node paints by presence.
  computeModule.setComputeReducer("preview", ({ name }) => ({ greeting: `Hi ${name}` }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { name: "string" },
      outputs: [], // greeting is NOT an output — it is a pure text sink
      fields: { name: makeField("name", "Ada") },
      texts: { greeting: text },
    }),
  )
  controller.recompute({ target: controller.element.querySelectorAll('[name="name"]')[0] })

  expect(text.textContent).toBe("Hi Ada")
})

test("compute resolves scoped bare names as [name=\"scope[x]\"] (issue #183)", () => {
  // Under data-reactive-scope="order", the bare compute name `cash` resolves to the
  // scoped DOM field [name="order[cash]"] — the same convention reactive_show uses.
  const cash = makeField("order[cash]", "0")
  const allowance = makeField("order[allowance]", "100")
  const total = makeField("order[total]", "500")
  computeModule.setComputeReducer("split", ({ allowance: a, total: t }) => ({ cash: t - a }))

  const controller = buildController(
    makeRoot({
      reducer: "split",
      inputs: ["allowance", "total"],
      outputs: ["cash"],
      scope: "order",
      fields: { "order[cash]": cash, "order[allowance]": allowance, "order[total]": total },
    }),
  )
  controller.recompute({ target: allowance })

  expect(cash.value).toBe("400") // resolved order[cash] and wrote it
})

test("an UNCHANGED text-node write is skipped (the change guard applies to textContent too)", () => {
  const fields = { title: makeField("title", "Hi") }
  const preview = makeTextNode("title_preview", "Hi")
  let writes = 0
  Object.defineProperty(preview, "textContent", {
    get() {
      return this._t ?? "Hi"
    },
    set(v) {
      writes++
      this._t = v
    },
  })
  computeModule.setComputeReducer("preview", ({ title }) => ({ title_preview: title }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { title: "string" },
      outputs: ["title_preview"],
      fields,
      texts: { title_preview: preview },
    }),
  )
  controller.recompute({ target: fields.title })

  expect(writes).toBe(0) // value already "Hi" → no write
})

test("an output writes to EVERY owned text node of that name (char counter + heading)", () => {
  const fields = { title: makeField("title", "abc") }
  const a = makeTextNode("title_preview", "")
  const b = makeTextNode("title_preview", "")
  computeModule.setComputeReducer("preview", ({ title }) => ({ title_preview: title }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { title: "string" },
      outputs: ["title_preview"],
      fields,
      texts: { title_preview: [a, b] },
    }),
  )
  controller.recompute({ target: fields.title })

  expect(a.textContent).toBe("abc")
  expect(b.textContent).toBe("abc")
})

test("a text node owned by a NESTED reactive root is NOT written", () => {
  const fields = { title: makeField("title", "Hi") }
  const nested = makeTextNode("title_preview", "keep")
  computeModule.setComputeReducer("preview", ({ title }) => ({ title_preview: title }))

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { title: "string" },
      outputs: ["title_preview"],
      fields,
      texts: { title_preview: nested },
    }),
  )
  // Re-point the mirror at a DIFFERENT root — it belongs to a nested component.
  nested._root = { id: "nested-root" }
  controller.recompute({ target: fields.title })

  expect(nested.textContent).toBe("keep") // untouched — not owned by this root
})

// ---------------------------------------------------------------------------
// Identity mirrors: sync a declared INPUT into its text node with NO reducer.
// ---------------------------------------------------------------------------

test("a declared input mirrors into its text node with NO registered reducer", () => {
  const fields = { title: makeField("title", "Live!") }
  const mirror = makeTextNode("title", "")
  // No setComputeReducer call — the identity-mirror pass must still run.

  const controller = buildController(
    makeRoot({
      reducer: "preview",
      inputs: { title: "string" },
      outputs: [],
      fields,
      texts: { title: mirror },
    }),
  )
  controller.recompute({ target: fields.title })

  expect(mirror.textContent).toBe("Live!")
})

test("the identity mirror uses the input's RAW string value (not a Number coercion)", () => {
  const fields = { title: makeField("title", "007 James") }
  const mirror = makeTextNode("title", "")

  const controller = buildController(
    makeRoot({ reducer: "none", inputs: { title: "string" }, outputs: [], fields, texts: { title: mirror } }),
  )
  controller.recompute({ target: fields.title })

  expect(mirror.textContent).toBe("007 James") // raw, not "7"
})

test("the identity-mirror write is change-guarded (unchanged value → no write)", () => {
  const fields = { title: makeField("title", "same") }
  const mirror = makeTextNode("title", "same")
  let writes = 0
  Object.defineProperty(mirror, "textContent", {
    get() {
      return this._t ?? "same"
    },
    set(v) {
      writes++
      this._t = v
    },
  })

  const controller = buildController(
    makeRoot({ reducer: "none", inputs: { title: "string" }, outputs: [], fields, texts: { title: mirror } }),
  )
  controller.recompute({ target: fields.title })

  expect(writes).toBe(0)
})

test("an ARRAY-form declared input also mirrors into its text node (untyped identity mirror)", () => {
  const fields = { total: makeField("total", "500") }
  const mirror = makeTextNode("total", "")

  const controller = buildController(
    makeRoot({ reducer: "none", inputs: ["total"], outputs: [], fields, texts: { total: mirror } }),
  )
  controller.recompute({ target: fields.total })

  // Raw field value mirrored (the display string), even though the array form
  // coerces the reducer's VALUES to Number.
  expect(mirror.textContent).toBe("500")
})
