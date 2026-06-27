# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
