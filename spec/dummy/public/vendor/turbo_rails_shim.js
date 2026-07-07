// Issue #187: pgbus's <pgbus-stream-source> client does
//   import { Turbo } from "@hotwired/turbo-rails"
// but the vendored turbo.js distribution (real Turbo 8.0.12) exports its
// symbols individually and only assigns `window.Turbo` — it has NO named
// `Turbo` export. Without one, pgbus's client module throws at load and the
// custom element never registers (SSE never connects, silently).
//
// This shim re-exports `window.Turbo` under the name pgbus imports. Importing
// it also runs turbo.js for its side effects (registering the turbo custom
// elements + setting window.Turbo), so a bare `import "@hotwired/turbo-rails"`
// (the dummy's own layout script, the cable cells) keeps working unchanged —
// the shim only ADDS the named export.
import "./turbo.js"

export const Turbo = window.Turbo
export default window.Turbo
