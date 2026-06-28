# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`reply.streams` — partial update with a token-only refresh (issue #30).**
  `reply.streams(Totals.update(@item))` emits **exactly** the streams you pass —
  no forced full-self replace — so an action can re-render only part of a
  component (one total cell, one sub-region) while the rest of the DOM, including
  a sibling `<input>` the user is mid-typing in, is left untouched. The signed
  identity token still rolls forward: the endpoint appends a tiny
  `<turbo-stream action="reactive:token">` (new `Streamable#to_stream_token`) that
  carries the fresh `data-reactive-token-value` and is applied by an inert client
  action — a pure attribute write on the root, so the focused field + caret
  survive. This unblocks spreadsheet-like per-field grid editing that the old
  "every reply re-renders the whole component" behavior made unusable (you had to
  reach for `data-turbo-permanent`). `Response.streams(self, *)` is the underlying
  builder; `reply.streams(*)` is the bound form. Backed by a new `render_self:
  false` + `token_component` path in the endpoint — the legacy full-self-replace
  refresh (`reply.replace` / `reply.with`) is unchanged.

- **`reply` — the action-reply builder.** Control an action's reply with
  `reply.replace` / `reply.morph` / `reply.update` / `reply.remove` /
  `reply.redirect(url)` / `reply.with(*)`, chaining `.flash` / `.stream` /
  `.also_update` / `.also_replace` as before. `reply` is a subject-bound facade on
  the component, so the two warts of the old form disappear: no `self` to thread
  (`reply.morph`, not `Response.morph(self)`) and no constant to qualify — a
  namespaced component no longer needs a per-file `Response = …` alias, because
  `reply` is a method resolved on the component, not a lexical constant. It
  returns the same immutable value object the endpoint reads, so the return-value
  contract, immutability, and chaining are unchanged. `Phlex::Reactive::Response`
  remains fully functional but is now an internal detail — `reply` is the
  documented surface.

- **Morph response — focus-preserving re-render (issue #28).**
  `reply.morph` (and the opt-in `reply.replace(morph: true)`)
  re-renders a component in place via Turbo 8's bundled Idiomorph
  (`<turbo-stream action="replace" method="morph">`) instead of an outerHTML
  swap. The focused `<input>` and its caret survive the save, making per-field
  reactive editing — a "spreadsheet" grid where a debounced save fires while the
  user is still typing/tabbing — actually viable. Backed by the new
  `Streamable#to_stream_morph` primitive and a `morph:` flag on the
  `.replace` / `.broadcast_replace_to` class builders and `#also_replace`
  (live cross-tab updates can morph too). The default everywhere stays the plain
  replace (no `method="morph"` attribute), so existing components are unchanged.
  No new dependency — Idiomorph ships with `turbo-rails >= 2.0`.
- **Input/select param-binding helpers (issue #23).** `reactive_input(:value,
  …)` and `reactive_select(:status, …) { … }` render a form control already bound
  to an action param — no hand-written `name: "value"` magic string to forget
  (which silently leaves the action with no params). `reactive_field(:param,
  **attrs)` returns just the attribute hash to spread onto any control; an
  explicit `name:` still wins as an escape hatch. The trigger stays on the
  button, so focusing the field doesn't dispatch and collapse edit mode.
- **`accepts_nested_attributes_for` helper (issue #24).** `nested_update!(:address,
  address)` maps a declared nested param straight onto `<assoc>_attributes` and
  carries the existing associated record's id, so `update_only:` matches it in
  place instead of building a second `has_one` — replacing the per-editor
  `*_attributes` + id-preservation boilerplate that was easy to get subtly wrong.
  `nested_attributes(:address, address)` returns the id-merged hash without
  updating, for combining with other attributes.
- **`Response#also_update` / `#also_replace` (issue #25).** Re-render a companion
  element alongside self without dropping to raw `turbo_stream_builder`:
  `Response.replace(self).also_update("page_heading", html: @record.name)` adds an
  update stream for an arbitrary DOM id (`html` is a string or a Phlex component,
  rendered through the configured renderer), and `.also_replace(other_component)`
  re-renders another Streamable component targeting its own `#id`. Both are
  immutable and additive, so the self-replace still refreshes the signed token.
- **Boot-time integration guards (issue #26).** Two silent first-run failures now
  surface a clear warning. A host catch-all route (`match "*path", …`) that
  shadows the engine's appended `POST /reactive/actions` (every reactive POST
  404s) is detected at boot via a route-recognition check
  (`Phlex::Reactive.action_route_ok?`), logging how to exempt the path. And when
  `data-controller="reactive"` elements are on the page but no controller
  connected — the `lazyLoadControllersFrom` case where the gem's controller was
  never registered — the client runtime logs a console warning naming the fix.
  The README gains an "Integration troubleshooting" section covering both.
- **Nested & array param types (issue #16).** Action param schemas can now
  declare arrays and nested hashes, not just scalars: wrap a type in an array
  (`bank_account_ids: [:integer]`) for an array param, or wrap a hash schema in
  an array (`invoice_items_attributes: [{ id: :integer, quantity: :float,
  _destroy: :boolean }]`) for Rails-style nested attributes. Coercion recurses
  per field, drops undeclared nested keys (no mass assignment), and accepts an
  array as either a JSON array or a Rails index hash (`{ "0" => …, "1" => … }`).
  A malformed (present-but-non-array) value for an array param is dropped — not
  coerced to `[]` — so a bad payload can't read as an explicit "clear all" on an
  `update!(declared_array:)`; a real empty array still passes through as `[]`.
  A reactive form can now mirror a normal nested-attributes update in one action
  instead of being forced into a per-row component architecture.
- **Debounce option on `on(...)` (issue #17).** A trigger can declare
  `on(:update, event: "input", debounce: 300)` (milliseconds) to coalesce rapid
  events — typically keystrokes — into a SINGLE action round trip fired after the
  quiet period, instead of one POST per keystroke. A `blur` flushes a pending
  dispatch so the last edit is never dropped, `preventDefault` still fires
  synchronously (a debounced `submit` won't navigate), and the debounced round
  trip still goes through the per-component queue so token threading holds.
  Omitting `debounce:` keeps the immediate-dispatch default.

### Performance

- **Re-render is ~2× faster with ~half the allocations.** `render_component` now
  renders through phlex-rails' lightweight `#render_in` against a memoized
  off-request view context, instead of `ActionController.renderer.render` (which
  dragged in ActionView's `TemplateRenderer`/`LookupContext`/log subscriber).
  Measured same-machine before/after: `render_component` 6.99k→14.1k i/s (212→99
  obj/call); `to_stream_replace` 4.60k→8.00k i/s (331→191 obj/call). HTML is
  byte-identical and the full Rails helper set (`dom_id`/`url_for`/`t`/CSRF) still
  works. The biggest win is on the **broadcast** path (N subscribers = N renders,
  no HTTP to amortize against); at the full-request level the Rails stack + DB
  dominate, so request throughput is roughly unchanged.

- **View context, Turbo `TagBuilder`, and flash builder are memoized** per
  component class (the comment used to claim this; now it's true). Keyed on the
  configured renderer's identity so swapping `Phlex::Reactive.renderer` rebuilds,
  and reset on Rails code reload (`config.to_prepare`) so a reloaded controller
  is never served stale.

- **Smaller per-render allocations on the token path.** `reactive_token`
  precomputes its ivar symbols + state string-keys per class (14→11 obj/call,
  state-backed), and `on(:action)` skips re-serializing an empty params hash
  (6→5 obj/call). The bracket-key regex in param coercion is hoisted to a frozen
  constant.

- **Client: the page-stable action path is resolved once per controller** instead
  of a `querySelector` per dispatch. CSRF token and pgbus connection id stay live
  (they can rotate).

- **Benchmark harness + CI report.** `rake bench` (micro: render/token/coerce) and
  `rake bench:request` (end-to-end via derailed) measure the hot paths; a CI
  `bench` job runs them on every PR and uploads the report as an artifact
  (run-and-report, not a hard gate). See `docs/performance.md` and the `/perf`
  command.

### Fixed

- **Model-scoped form fields feed a nested param (issue #21).** A Rails
  `Form(model: @invoice)` posts flat bracketed keys (`invoice[date]`,
  `invoice[status]`) because the client keeps each input's `name` verbatim. The
  server did exact-key matching, so a nested schema (`params: { invoice: { date:
  :string } }`) looked for the literal key `"invoice"`, never found it, and
  dropped the whole param. Param normalization now expands bracket notation
  before coercion — `invoice[date]` nests under `invoice`, and
  `items_attributes[0][qty]` becomes the Rails index-hash form the array coercer
  already understands. A nested schema matches a normal Rails form with zero
  field renaming, which is what makes the issue #16 nested-param types useful for
  real forms. Pre-nested objects, plain scalars, and non-string values (a
  checkbox boolean) pass through unchanged.
- **Nested reactive roots no longer leak fields (issue #15).** When a reactive
  component is rendered inside another (both are `data-controller="reactive"`
  roots), an action on the outer root previously swept *every* descendant named
  input — including the nested roots' inputs — into its own params. Field
  collection now stops at nested reactive roots: an action collects only the
  inputs whose nearest `[data-controller~="reactive"]` ancestor is its own root.
  Outer flat fields and per-row reactive editing compose cleanly, with no
  name-disjointness workarounds.

## [0.2.6]

### Added

- **Action response control via `Phlex::Reactive::Response`.** An action MAY now
  return a `Response` to govern the actor's HTTP reply, instead of only the
  implicit single re-render. Returning anything else keeps the legacy default
  (re-render the component in place), so existing actions are unaffected.
  - `Response.replace(self)` / `.update(self)` — explicit re-render.
  - `Response.replace(self).flash(:error, msg_or_component)` — surface a
    validation error / notice (the `#1` driver). `.flash` is additive on a
    self-replace, so the component's signed token always refreshes. Flash
    content is supplied explicitly (the render context is off-request — there is
    no Rails `flash`); pass a string or a Phlex component. Target container is
    `Phlex::Reactive.flash_target` (default `flash`).
  - `Response.remove(self)` — drop the element (e.g. a moderation queue). New
    instance helper `Streamable#to_stream_remove` backs it.
  - `Response.redirect(url)` — client-side `Turbo.visit` for when the current
    URL is dead (e.g. a slug rename). Rides a 200 turbo-stream carrying a
    `reactive:visit` custom action (registered in the client), **not** an HTTP
    3xx (which the client bails on). Pass a `*_url`.
  - `Response.with(*streams)` / `#stream(*more)` — multi-stream (replace self +
    a sibling component).
- The endpoint guarantees the component's own replace is present (token refresh)
  for non-remove/redirect responses, and never double-prepends when the action
  already included a self-targeted stream.

## [0.2.5]

### Fixed

- **Form submit navigated instead of running the reactive action.** A component
  wired with `on(:save, event: "submit")` on a real `<form>` let the browser
  submit natively (full POST to the form's `action`), because
  `dispatch()` deferred `event.preventDefault()` into the request-queue microtask
  — too late, since `preventDefault()` only works synchronously within the event
  dispatch. For `click` triggers there's no default to miss, so it was invisible;
  for `submit` the form navigated (e.g. `POST /` → routing error). `dispatch()`
  now calls `preventDefault()` synchronously (and captures the action/params up
  front, so the deferred work never re-reads a reset event object). Guarded by a
  bun unit test (`spec/javascript/reactive_controller.test.js`) that asserts the
  synchronous call and fails on the pre-fix deferred code. Closes #11.

## [0.2.4] - 2026-06-24

### Fixed

- **Reactive save silently dropped rich-text / custom-editor fields.** The
  client's field auto-collection (`#collectFields`) queried only
  `input[name], select[name], textarea[name]`, so a named rich-text editor
  (`lexxy-editor`, `trix-editor`) or any `[contenteditable]` was skipped — a
  reactive `save` posted an empty value and silently wiped the field, with no
  error. `#collectFields` now also reads named custom editors and contenteditable
  elements (by `name` *attribute*, since a plain element has no `name` IDL
  property), reading the serialized `.value` else the contenteditable text. It
  only fills a name the standard controls left absent or empty, so a hidden input
  a rich editor mirrors into (e.g. Trix) still wins when populated. The vendored
  client copy the system suite runs (`spec/dummy/public/vendor/...`) is now kept
  byte-identical to source by a guard spec, so the browser tests never validate
  stale client code again. Closes #8.

## [0.2.3] - 2026-06-24

### Fixed

- **Record-backed components silently lost `reactive_state` every action.** When
  a component declared BOTH `reactive_record` and `reactive_state`, the state
  branch was dead: `reactive_token` signed only the record GID and
  `from_identity` rebuilt with only the record — so the listed instance vars
  (e.g. `attribute`, `editing`) reset to their `initialize` defaults on every
  action. This broke the documented `inline_edit` example (clicking "edit"
  couldn't stay in edit mode; `save` wrote the wrong/blank column) and quietly
  voided the docs' promise that `@attribute` is signed/tamper-proof.
  `reactive_token` now signs the record GID AND the declared state into one
  `MessageVerifier` payload, and `from_identity` restores both — record + state
  are composable, and the state stays tamper-proof. Record-only (`{c, gid}`) and
  state-only (`{c, s}`) token shapes are unchanged; a signed `false` survives the
  round trip (only a genuinely absent value falls back to the `initialize`
  default). No API changes. Closes #6.

### Documentation

- Documented the combined record + state identity (the `{c, gid, s}` token
  shape): the README, `docs/architecture.md`, and `docs/security.md` no longer
  frame `reactive_record` and `reactive_state` as mutually exclusive. (#9)

## [0.2.2] - 2026-06-24

### Fixed

- **Record-backed component built with a different init keyword by the action
  endpoint vs the broadcast path.** The click path (`Component.from_identity`)
  builds with `reactive_record_key` (the `reactive_record :name`), but the
  broadcast path (`Streamable.build` → `model_param_name`) built with the
  demodulized, underscored class name. They only agreed when the class name
  happened to equal the record name — otherwise one path worked and the other
  raised `ArgumentError: missing keyword`. The README's own `Todos::Item`
  (`reactive_record :todo`, `Item` ≠ `todo`) hit this on broadcast.
  `model_param_name` now prefers `reactive_record_key` when set, so a single
  `initialize(<record>:)` satisfies both clicks and broadcasts. `Streamable`-only
  components (no `reactive_record`) keep the demodulized-class-name default, and
  an explicit `def self.model_param_name` override still wins. No API changes.
  Closes #4.

## [0.2.1] - 2026-06-24

### Fixed

- **Zeitwerk eager-load crash in host apps.** A host app with
  `config.eager_load = true` (the production default) runs
  `Zeitwerk::Loader.eager_load_all`, which walked this gem's loader and raised
  `Zeitwerk::NameError` on two files that don't follow Zeitwerk's
  file→constant rule: `version.rb` (defines `VERSION`, not `Version`) and the
  Rails generators under `lib/generators` (whose path/constant scheme is
  intentionally non-Zeitwerk). The loader now requires `version.rb` up front and
  ignores it, and ignores `lib/generators` (Rails loads generators itself), so
  the gem eager-loads cleanly. Added a regression spec that calls
  `eager_load_all`. No API changes.

## [0.2.0] - 2026-06-24

### Added

- **Actor-echo suppression.** `broadcast_*_to` now accepts `exclude:` (and
  `visible_to:`), forwarded to the stream transport. Pass
  `exclude: reactive_connection_id` from an action so the actor doesn't receive
  the echo of its own broadcast — making `append`/`prepend` and optimistic UI
  safe. The client sends its SSE connection id as `X-Pgbus-Connection`; the
  endpoint exposes it via `Phlex::Reactive.current_connection_id` /
  `reactive_connection_id`. Honored by pgbus; ignored (harmless) on Action Cable.

### Requires

- **pgbus >= 0.9.4** when using `exclude:`/`visible_to:` — it ships the
  `exclude:`/`visible_to:`/`event:` forwarding through Turbo's broadcast
  helpers. phlex-reactive still works on Action Cable without pgbus; the
  `exclude:` argument is simply ignored there.

## [0.1.0] - 2026-06-20

### Added

- `Phlex::Reactive::Streamable` — class methods (`replace`, `update`, `append`,
  `prepend`, `remove`) and broadcast methods (`broadcast_replace_to`, ...) that
  render a Phlex component as an auto-targeted Turbo Stream by its stable `id`.
- `Phlex::Reactive::Component` — declare client-invokable `action`s with a param
  schema; `reactive_record` (record-backed, GlobalID identity) and
  `reactive_state` (record-less, signed state); `reactive_attrs` and `on(...)`
  view helpers.
- `Phlex::Reactive::ActionsController` — one signed-identity endpoint behind all
  reactive components; default-deny actions, schema-coerced params,
  transactional action execution.
- Generic `reactive` Stimulus controller — per-component request serialization,
  synchronous token threading, auto field collection; no per-feature controllers.
- Rails engine — mounts the action endpoint, registers and auto-pins the client
  runtime for importmap apps.
- **Generators.** `rails g phlex:reactive:install` registers the `reactive`
  Stimulus controller (eagerly) and writes a config initializer.
  `rails g phlex:reactive:component Name [actions] [--record name | --state vars]`
  scaffolds a reactive component (and an RSpec spec when the app uses RSpec),
  state-backed by default or record-backed with `--record`.

[Unreleased]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.3...HEAD
[0.2.4]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mhenrixon/phlex-reactive/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mhenrixon/phlex-reactive/releases/tag/v0.1.0
