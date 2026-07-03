// The JS twin for the reactive_text + typed-compute example (issue #104).
// Registered under the "preview" reducer key. The typed input `title` arrives as
// a RAW string (inputs: { title: :string }), so `.length` is the character count
// — NOT a Number coercion. The lone output, char_count, has no matching form
// field, so the controller writes it to the [data-reactive-text="char_count"]
// node via textContent. The live preview HEADING needs no reducer output — it's
// an identity mirror of `title` (the always-run mirror pass handles it).
import { setComputeReducer } from "phlex/reactive/compute"

export function registerPostPreview() {
  setComputeReducer("preview", ({ title }) => ({
    char_count: `${title.length}/80`,
  }))
}
