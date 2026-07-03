// Micro-bench: recompute — the PUBLIC client-side compute (data-binding) entry
// point (issue #104). On `input`, it runs a registered JS reducer over the
// declared input fields and writes the outputs with NO round trip — the
// "instant" half of the new/unpersisted-record UX. Called directly (it's a
// public method), the way reactive_compute.test.js drives it.
//
// A 30-input happy-dom calculator: 30 numeric inputs feeding a reducer that sums
// them into one output field. recompute reads every declared input (the
// #ownedField walk per name), runs the reducer, and writes the changed output —
// so this measures the full per-keystroke compute cost on a realistically wide
// calculator (the payment_split / line-item shape).
//
// happy-dom numbers are ENGINE-RELATIVE (see the docs performance page): a valid
// same-machine before/after delta, NOT an absolute browser cost.

import { bench, group } from "mitata"
import { makeDom, buildController, buildCalculator } from "./support/harness.js"

const { document } = await makeDom()
globalThis.document = document
globalThis.window = document.defaultView

const { root, firstInput } = await buildCalculator(document, { fieldCount: 30 })
const controller = buildController(root)

// A synthetic input event whose target is the first declared input, so
// meta.changed resolves to a real field name — the per-keystroke shape.
const event = { target: firstInput }

group("recompute (30-input calculator, reducer sum → one output)", () => {
  bench("30 inputs → sum output", () => controller.recompute(event))
})
