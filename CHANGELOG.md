# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.2.1]

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

## [0.2.0]

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

## [0.1.0]

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

[Unreleased]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mhenrixon/phlex-reactive/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mhenrixon/phlex-reactive/releases/tag/v0.1.0
