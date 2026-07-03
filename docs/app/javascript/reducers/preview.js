import { setComputeReducer } from "phlex/reactive/compute"

// The client twin of PostPreviewComponent#char_count (the Ruby seed). Registered
// under the "preview" reducer key, it recomputes the character counter IN-BROWSER
// on every `input` — no round trip. The identity mirror (the title heading) needs
// no reducer output; only the derived char_count does.
//
// Keep this in lockstep with the Ruby seed (`"#{title.length}/80"`): the whole
// point of reactive_compute is one math contract, two execution sites (the client
// paints instantly, the server re-render reconciles to the identical value).
setComputeReducer("preview", ({ title }) => ({
  char_count: `${(title ?? "").length}/80`,
}))
