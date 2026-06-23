# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Generators.** `rails g phlex:reactive:install` registers the `reactive`
  Stimulus controller (eagerly) and writes a config initializer.
  `rails g phlex:reactive:component Name [actions] [--record name | --state vars]`
  scaffolds a reactive component (and an RSpec spec when the app uses RSpec),
  state-backed by default or record-backed with `--record`.

## [0.2.0]

### Added

- **Actor-echo suppression.** `broadcast_*_to` now accepts `exclude:` (and
  `visible_to:`), forwarded to the stream transport. Pass
  `exclude: reactive_connection_id` from an action so the actor doesn't receive
  the echo of its own broadcast — making `append`/`prepend` and optimistic UI
  safe. The client sends its SSE connection id as `X-Pgbus-Connection`; the
  endpoint exposes it via `Phlex::Reactive.current_connection_id` /
  `reactive_connection_id`. Honored by pgbus; ignored (harmless) on Action Cable.
  Requires pgbus with `exclude:` Turbo forwarding.

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

[Unreleased]: https://github.com/mhenrixon/phlex-reactive/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/mhenrixon/phlex-reactive/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mhenrixon/phlex-reactive/releases/tag/v0.1.0
