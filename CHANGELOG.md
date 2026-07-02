# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Single include + a default `#id` for record-backed components (#81).**
  `include Phlex::Reactive::Component` now pulls in
  `Phlex::Reactive::Streamable` automatically (ActiveSupport::Concern's
  dependency mechanism includes Streamable into the base FIRST — exactly the
  manual order the old two-include ceremony established), so one include is
  enough; the legacy explicit double include remains a harmless no-op. And a
  record-backed component (`reactive_record :todo`) gets `#id` for free:
  `dom_id(record)` via the render-context-free `Streamable#dom_id` — the id
  virtually every such component wrote by hand. An explicit `def id` always
  wins (normal method lookup). Deliberately NO class-name default for
  state-backed components — they're frequently multi-instance, so a class-name
  id would silently collide; they (and bare Streamable classes) keep the loud
  `NotImplementedError`, now with a message that says how to fix it. Caveat:
  two different component classes rendering the SAME record on one page
  collide on the default — give one a prefixed id
  (`def id = dom_id(@todo, "rich")`). The component generator emits the new
  short form. Same-machine `rake bench` before/after: allocations on the
  render/token hot paths are byte-identical (192 obj per `to_stream_replace`,
  100 per `render_component`, 47 per record-backed token, retained 0) and
  throughput is unchanged within run-to-run noise — the default costs one
  `respond_to?` + two memoized reads, and only for components that didn't
  define `#id`.

- **`reactive_compute` reducers are told which field changed — one reducer can
  express a multi-way/mutual rebalance (#75).** A compute reducer now receives a
  second argument, `meta = { changed }`: the name of the declared input the
  triggering `input` event edited, or `null` (a direct `recompute()` call, or a
  target this root doesn't own / didn't declare as an input — nested reactive
  roots stay excluded per #15). That's exactly what the mutual-rebalance shape
  ("three fields that must always sum to a total") needs — given the same value
  snapshot, the reducer branches on WHICH field is the free/derived one:

  ```js
  setComputeReducer("three_way_split", ({ field_a, field_b, field_c, total }, { changed }) => {
    if (changed === "field_c") return { field_a: total - field_c - field_b }
    return { field_c: total - field_a - field_b }
  })
  ```

  Fully backward compatible: a one-argument reducer just ignores `meta` — no
  Ruby DSL change, no markup change. One contract to know: because an output
  write dispatches a real change-guarded `input` event (#76), `recompute`
  re-enters with `changed` = the OUTPUT field's name (when it's also a declared
  input), so a branching reducer must be **convergent** — the re-entrant pass
  must compute the values already in the DOM so the change guard settles the
  chain (the example above does: deriving `field_a` back from the just-written
  `field_c` reproduces its current value; no write, no event, settled in one
  bounce). Documented in `compute.js`'s header and the `reactive_compute` docs;
  covered by bun unit tests including the issue's three-way rebalance verbatim
  with a bounded reducer-call count.

- **`Phlex::Reactive.verbose_errors` — diagnostic endpoint error bodies +
  dropped-param logging (#82).** An endpoint failure used to be a bare
  `head 400/403/404` and a silently-dropped param left no trace — debugging
  "nothing happens" meant reading the gem source. Now every failure is
  warn-logged as `[phlex-reactive] …` in EVERY environment, and with
  `verbose_errors` on (default `Rails.env.local?` — development AND test; off
  in production) the response also carries a plain-text diagnostic body the
  client already prints via `console.error`: a tampered/stale token (400,
  distinguishing signature-invalid from a token class that no longer resolves
  from a class that isn't reactive — `InvalidToken` now carries a `diagnostic`),
  an undeclared action (403, listing the declared actions), a registered
  authorization error (403, naming the error class and the action), and a
  missing record (404, naming the GlobalID). Param coercion additionally logs
  every dropped key with its full bracketed path and reason
  (`undeclared` / `uncoercible`), hinting when a flat name looks like the
  bracketed twin of a declared nested key (the #16/#21 confusion). Statuses
  never change with the flag, the client needs no changes, and the production
  coercion path does zero extra work (nil collector, early-return guards) —
  `rake bench:one[coerce_params]` before/after is unchanged within noise

- **Client lifecycle CustomEvents — `reactive:before-dispatch` /
  `reactive:applied` / `reactive:error` with `retry()` (#79).** The generic
  controller now dispatches three bubbling, composed events around every action
  round trip, so an app can toast an error, veto a dispatch, instrument latency,
  or build retry UI without forking the one controller.
  `reactive:before-dispatch` is cancelable and fires once per user gesture —
  post-`preventDefault`, post-`confirm:`, PRE-debounce — with
  `{ action, params, element }`; `event.preventDefault()` skips the round trip
  entirely (nothing is scheduled, debounced or not). `reactive:applied` fires
  with `{ action, params, html }` after the fresh token was captured and the
  streams were handed to `Turbo.renderStreamMessage` (Turbo applies them
  asynchronously — listen to Turbo's own events for post-morph timing).
  `reactive:error` fires in every failure branch with
  `{ action, params, kind, status?, body?, retry? }` where `kind` is one of
  `redirected | http | content-type | network` (all retriable) or `apply` —
  the fetch itself succeeded and the server already completed the mutation,
  but something AFTER it threw INSIDE THE CONTROLLER (a malformed response, a
  Turbo render error — NOT a throwing `reactive:applied` listener, whose
  exception `dispatchEvent` never propagates back per the DOM spec, so it
  can't reach this catch); `apply` carries NO `retry` at all, since retrying
  would re-POST an action that already succeeded. `retry()`
  (when present) re-enters the request queue — re-reading the freshest signed
  token and re-collecting the fields at send time, refiring no second
  before-dispatch — and no-ops with a `console.warn` once the component left
  the DOM. Events go out via raw
  `dispatchEvent` (Stimulus's `this.dispatch` helper is shadowed by the
  controller's own `dispatch` action method) on the root element, falling back
  to `document` when a plain replace detached it; the existing `console.error`
  logging is unchanged. Composes with plain Stimulus listening —
  `data-action="reactive:error->toast#show"` on an ancestor. Covered by unit
  (JS) and real-browser system specs; README "Failure UX & lifecycle events"
  and the security docs page document the contract.

- **Combobox keyboard navigation — `on(:search, …, listnav: "[role=option]")` (#72).**
  A search/combobox trigger can now declare client-side list navigation: Arrow
  Up/Down move a highlight among the option elements IN-BROWSER (no round trip),
  Enter picks the highlighted option by clicking its own `on(:select)` trigger
  (so the selection stays a normal signed reactive action), and Escape clears —
  all without a bespoke Stimulus controller. `listnav:` appends Stimulus's native
  keyboard filters (`keydown.down/up/enter/esc->reactive#listnav*`) to the input's
  `data-action` and marks the option selector; the generic controller's `listnav*`
  handlers own the ephemeral highlight (a `data-reactive-highlighted` attribute,
  never shipped as trusted state), mirroring `#recompute`. Only the highlight is
  client-side — selection is still a default-deny, signed action. No new client
  module (the handlers live in the existing controller); covered by unit (JS),
  request, and real-browser system specs green under Puma AND Falcon.

- **Keyboard triggers on `on(...)` via `event:` — Enter-to-submit /
  Escape-to-cancel with no client JavaScript.** `event:` is interpolated straight
  into the Stimulus action descriptor, so **Stimulus's native keyboard filters
  just work**: `on(:add, event: "keydown.enter")` emits
  `keydown.enter->reactive#dispatch` and the action fires only on Enter, not on
  every keypress. `event: "keydown.esc"` gives Escape-to-cancel. No new option to
  learn (it's Stimulus's own filter syntax), no client change, no vendored-client
  re-sync — and, deliberately, **no reserved `key:` keyword**, so `key` stays a
  normal action-param name (`on(:switch, key: "pgbus")` keeps passing `key`
  through as a param — no backward-incompatibility). Because a keyboard trigger
  isn't a click, it does not get the `type="button"` a click trigger does. One
  action per element still holds — bind Enter-save and Escape-cancel to separate
  elements. README documents it under "Keyboard triggers".
- **`reactive_compute` — client-side data bindings (no round trip).** A component
  can now declare a client-side computation that recomputes derived fields
  IN-BROWSER on `input`, with NO server round trip — the "instant" half of a
  new/unpersisted-record UX that previously required a hand-written Stimulus
  controller (e.g. an order calculator that rebalances a payment split as you
  type). Declare the binding in Ruby and register the matching reducer once in JS:

  ```ruby
  reactive_compute :payment_split,
    inputs:  %i[allowance cash leasing total],   # fields the reducer reads
    outputs: %i[allowance cash leasing]          # fields it writes (no POST)
  # in the view: div(**mix(reactive_root, reactive_compute_attrs(:payment_split)))
  # on the edited field: data-action="input->reactive#recompute"
  ```

  ```js
  import { setComputeReducer } from "phlex/reactive/compute"
  setComputeReducer("payment_split", ({ allowance, cash, leasing, total }) => ({
    allowance, leasing, cash: total - allowance - leasing,
  }))
  ```

  The generic controller runs the named reducer on `input`, writes only the
  declared outputs (leaving the edited field + caret alone), and — for each
  output whose value actually changed — dispatches a bubbling `input` event on
  the field so a chained summary repaints, matching the server's `set_value` +
  `dispatch("input")` contract (see #76). A missing/unregistered reducer is a
  no-op (a page never breaks because a binding wasn't wired up). When the same
  component ALSO carries `on(...)` (a persisted record, or a draft you sync), that
  debounced POST still fires and the server reply reconciles — so `reactive_compute`
  is the optimistic client paint, the server round trip is the source of truth.
  One math contract, two execution sites. New client module
  `phlex/reactive/compute` (auto-pinned by the engine like `confirm`).

- **Draft (unpersisted-record) tokens — `reactive_record` no longer crashes on a
  `new_record?`.** A record-backed component may now render an UNSAVED record (an
  order the user is building before it's saved). `reactive_token` omits the `gid`
  when the record isn't persisted (`to_gid` would raise `MissingModelIdError`) and
  relies on the declared `reactive_state` as the draft seed, so the token still
  signs cleanly and the client controller mounts. The draft is driven client-side
  (`reactive_compute`) until it's saved; once persisted, a re-render signs the
  `gid` as before. Combined with `reactive_compute`, this is the "persisted → server,
  new → in-browser" split as a first-class capability instead of a hand-rolled one.

- **Overridable / async confirm resolver — reuse your themed dialog (#55).**
  Follow-up to #52. The `confirm:` gate was hardcoded to the synchronous,
  browser-native `window.confirm`, so a reactive trigger was the one interaction
  a Hotwire app couldn't theme — every confirmable reactive action showed the
  unstyled native chrome instead of the app's `Turbo.config.forms.confirm`
  dialog. The client now resolves the confirmation through an overridable hook
  (`confirmResolver`, set via `setConfirmResolver` from `phlex/reactive/confirm`),
  defaulting to `window.confirm`. An app reuses its styled dialog in one line:
  `setConfirmResolver((m) => window.Turbo.config.forms.confirm(m))`. The resolver
  may be **async** — `dispatch` `preventDefault`s up front (preserving the #11
  submit-trigger guarantee), then `await`s the resolver and enqueues only on a
  truthy result; a falsy resolve or a rejection cancels the action and never
  leaks an unhandled rejection. Unset, behavior is byte-for-byte identical to
  0.4.5 (sync native confirm, no dependency); the `confirm:` markup/`on(...)` API
  is unchanged. README documents the one-line opt-in.

- **`reactive_root` helper — the whole reactive root in one spread (#48).**
  `reactive_attrs` doesn't emit `id:`, so an app could put `id:` on a *child*
  element and leave the controller root's `id` empty — which silently re-opened
  the #46 add-once-only bug (the client falls back to the first token in the
  response, the next action POSTs a foreign token, and the endpoint 403s).
  `div(**reactive_root)` emits the component `id` **and** `reactive_attrs` on one
  element, so the id can't land on the wrong node; `reactive_root(class:, data:)`
  deep-merges via `mix`, and an explicit `id:` override still wins. `reactive_attrs`
  is unchanged — existing `div(id:, **reactive_attrs)` components keep working. The
  generic Stimulus controller now also `console.warn`s on `connect()` when a
  reactive root has an empty `id`, so the failure surfaces on page load (a one-line
  hint) instead of on the second click. README/docs promote `div(**reactive_root)`.

- **File / multipart params in a reactive action (#34).** An action can now accept
  an uploaded file: declare `params: { file: :file }` (or `[:file]` for multiple).
  When the reactive root holds a populated `<input type="file">`, the client sends
  the action as multipart `FormData` instead of JSON — `token` + `act` + scalar
  params as fields, the file(s) appended — and the endpoint coerces `:file` to the
  `ActionDispatch::Http::UploadedFile`, passed through untouched. A non-file value
  sent to a `:file` param is dropped (the keyword default applies), consistent with
  the #16 coercion rules — and for a `[:file]` array, a non-file *element* (a
  forged/mixed payload) is rejected from the array too, so the internal coercion
  sentinel never leaks to the action. A `<input type="file" multiple>` keeps its
  array shape (`params[name][]`) even when the user picks exactly one file, so a
  `[:file]` schema still coerces it. Token threading and the re-render/morph are
  identical; only the request encoding changes when a file is present — so
  attaching a document/receipt/image stays a reactive action instead of dropping
  out to a bespoke controller + upload Stimulus controller. Covered end-to-end:
  server coercion (request specs), the FormData wire shape (bun unit tests), and a
  real browser upload under Puma + Falcon (system spec).

### Documentation

- **Corrected the broadcast render-cost mental model — "N subscribers = N
  renders" was wrong (#78).** A `broadcast_*_to` call renders the component
  ONCE and passes the finished `html:` to `Turbo::StreamsChannel`, so every
  subscriber of that stream shares one payload (the per-subscriber cost is
  transport-side). The render cost is per CALL — broadcasting one change to K
  different stream keys is K builds + K renders + K token signings of
  byte-identical HTML — and per-viewer rendering (`visible_to:`-style content)
  is the irreducible render-per-viewer case. Fixed in the performance docs
  page, the render micro-bench comment, and CLAUDE.md; also repointed stale
  `docs/performance.md` references to the docs app's performance page
  (`docs/app/views/docs/pages/performance.rb`). No behavior changed.

- **The auto-collected-params contract, spelled out (#64, #65, #66, #67).** Four
  gaps surfaced from building one model-scoped form (numeric fields that rebalance
  live). No behavior changed — the README now documents what the code already
  does:
  - **#67** — a **flat** param schema silently drops **bracketed** field names.
    Because the endpoint expands `invoice[date]` to `{ "invoice" => { … } }`
    *before* matching the schema, a flat `{ date: … }` matches nothing and the
    action gets keyword defaults with no error. The "Model-scoped form fields"
    section now warns to nest the schema under the model key to match the names.
  - **#65** — auto-collected sibling fields are read **at dispatch time**, not
    from a pre-event snapshot: a `change`/`input` trigger sees its own new value
    and every peer's current DOM value. Documented in a new "Auto-collected
    sibling fields — the read contract" subsection.
  - **#66** — reactive collection **includes `disabled` fields**, deliberately
    unlike a native `<form>` submit, so a read-only computed field (a synced
    `total`) reaches the action. Documented as intentional, with the `readonly`
    vs `disabled` guidance for form-submit parity.
  - **#64** — a `reactive_record` action can use the record for **identity +
    authorization only** and compute over live, unsaved params, returning
    `reply.streams(...)` to stream a partial update with **no persist and no
    broadcast**. Documented as a first-class "record-authorized, transient-state
    action" pattern in the `reply` section.

  The demo app (`docs/`) gains a **live payment-split rebalancer** example — three
  amounts that always sum to a total, editing one rebalances the peers — that
  makes #64–#67 browsable (model-scoped bracketed params, a disabled computed
  field the action still reads, siblings collected at dispatch, transient compute
  with no persist/broadcast). The **todo** and **inline-edit** examples gain
  Enter-to-add / Enter-to-save / Escape-to-cancel via the new `key:` filter,
  covered by request specs and a real-browser (Playwright) Enter-keypress test.
  Combobox keyboard navigation is tracked separately (#72) for the
  minimal-client-seam work.

### Changed

- **Linter: Standard → RuboCop.** The gem now lints with RuboCop (all new cops
  enabled, `NewCops: enable`) instead of StandardRB, so the suite teaches and
  enforces newer Ruby idioms that Standard leaves alone — chiefly the Ruby 3.4
  `it` implicit single block parameter (`map { it.foo }`) via
  `Style/ItBlockParameter: always`. The whole tree was autocorrected; the
  lib/app changes were the `|x| x.foo` → `it.foo` rename plus hash-brace
  spacing — behavior is unchanged and all specs are green. The gemspec and
  Rakefile are excluded from `Style/ItBlockParameter` (their `do |spec| … end`
  config blocks read better named); a nested Phlex content block and a scope
  lambda carry inline disables where blanket `it` would collapse two parameters
  or break a `where(room:)` kwarg shorthand; and blocks that fed a
  keyword-argument shorthand (`Component.new(todo:)`) were rewritten to an
  explicit `Component.new(todo: it)` so the `it` rename can't silently change
  the keyword. Component-
  aware relaxations (line length, `Lint/MissingSuper`, unused action params)
  are scoped to `spec/dummy/app/components/**`. `bundle exec standardrb` is now
  `bundle exec rubocop`; `rake`'s default runs `spec + rubocop`.
- **Added `rubocop-capybara` and `rubocop-thread_safety`.** Capybara lints the
  browser specs (clean today — the suite already uses waiting matchers).
  thread_safety stays on as a tripwire for unsafe shared mutable state on the
  request/broadcast path; its `ClassInstanceVariable` /
  `ClassAndModuleAttributes` cops are scoped off only in the three files whose
  flagged class-level state is deliberate and audited — module-level config
  (`lib/phlex/reactive.rb`, set once at boot), class-definition-time DSL
  registries (`component.rb`), and the per-thread view-context cache's integer
  generation counter (`streamable.rb`). An adversarial audit confirmed none are
  request-path hazards; the lazy `||=` config defaults are idempotent. (A
  follow-up may warm `verifier`/`renderer` at boot to remove even the
  benign-by-idempotency first-call race — out of scope for this lint change.)

### Removed

- **Dropped the `standard` development dependency** in favor of `rubocop`,
  `rubocop-capybara`, `rubocop-performance`, `rubocop-rake`, `rubocop-rspec`,
  and `rubocop-thread_safety`.

### BREAKING

- **Minimum Ruby is now 3.4** (was 3.2). Enabling the `it` block parameter
  requires Ruby 3.4, so `required_ruby_version` is `>= 3.4.0` and the CI matrix
  drops 3.2 and 3.3. Stay on phlex-reactive 0.3.x if you need Ruby 3.2/3.3.

### Fixed

- **`reactive_compute` output writes never fired real `input` events — chained
  repaints were dead in production (#76).** The controller's `recompute()` wrote
  each output with a bare `field.value = …` under a comment claiming the write
  fires the field's `input` listeners. Only the bun-test fake's custom `value`
  setter did that — real browsers never fire `input` on a programmatic `.value`
  write — so anything listening on a computed field (a chained summary repaint,
  a second compute) silently never ran outside the test suite. The controller now
  dispatches a real bubbling `new Event("input")` after each output write, and
  the write is **change-guarded**: a field is written (and the event dispatched)
  ONLY when the reducer's value differs from the field's current value
  (String-compared). The guard is load-bearing, not an optimization — the shipped
  `payment_split` example declares overlapping inputs/outputs, so an
  unconditional dispatch would re-enter `input->reactive#recompute` forever;
  with the guard, chains settle deterministically (the re-entrant pass writes
  nothing and stops). The bun-test fake now matches real DOM (no auto-fire on
  `.value` assignment; listeners run only through the controller's explicit
  `dispatchEvent`), with unit coverage for the unchanged-write no-op, the
  single bubbling dispatch, loop termination on the payment_split shape, and a
  chained listener firing via the dispatched event — plus a real-browser system
  assertion that a derived field repaints after typing. The misleading comments
  in `reactive_controller.js` and `compute.js` now describe the real contract.

- **`reply.flash` discarded its level — `:error` and `:notice` emitted
  byte-identical streams (#77).** `Response.flash_stream` declared the level as
  `_level` and never used it, so an app could not style errors red without
  abandoning the flash helper — while the public API and every README example
  pass a level. String flash content is now wrapped in
  `<div class="reactive-flash reactive-flash--{level}"
  data-reactive-flash-level="{level}">…</div>`, so the level reaches the wire as
  a style hook (class) and a script/test hook (data attribute); the level is
  HTML-escaped before landing in either attribute. **This intentionally changes
  the wire output for string flashes** (previously the bare string was appended
  with no wrapper) — restyle against `.reactive-flash--{level}` if you targeted
  the raw text node. The string itself keeps the exact pre-existing injection
  contract, now applied inside the wrapper: a plain String is HTML-escaped, an
  `html_safe` String passes verbatim. Phlex **component** content still renders
  VERBATIM — byte-identical to before, no wrapper (the caller owns the markup;
  a spec pins it). New config `Phlex::Reactive.flash_component = MyFlash`
  (default nil) renders string flashes through your own component instead of
  the default wrapper — instantiated `MyFlash.new(level:, content:)` and
  rendered through the existing render path; component content bypasses it.

- **`reactive_controller.js` used a relative `./confirm.js` import that 404'd under
  importmap-rails + Propshaft — taking down every Stimulus controller on the page (#57).**
  The #55 confirm resolver added `import { confirmResolver } from "./confirm.js"` to the
  client controller. Under importmap + Propshaft the controller is served at its
  **digested** URL, and a relative sibling import is left untouched (Propshaft's JS
  compiler rewrites only `RAILS_ASSET_URL(...)`, and the import map resolves **only**
  bare specifiers, never relative-resolved URLs). So the browser resolved `./confirm.js`
  against the digested controller URL and requested an **undigested**
  `/assets/phlex/reactive/confirm.js` → **404**. The throwing import meant
  `reactive_controller.js` never evaluated, and in an app that eagerly registers it the
  whole controllers entrypoint died — **every** Stimulus controller on the page stopped,
  with no obvious link to phlex-reactive. The fix imports the **bare** specifier the
  engine already pins (`phlex/reactive/confirm`), which resolves to the digested asset
  through the import map and mirrors how the gem already expects apps to import the
  module (`import { setConfirmResolver } from "phlex/reactive/confirm"`). Bundlers
  (esbuild/webpack/bun) resolve the bare specifier the same way they already resolve
  `phlex/reactive/reactive_controller`; the gem's bun JS suite resolves it via a new
  `tsconfig.json` `paths` alias. Covered by a bun unit test (the bare import resolves,
  and the source no longer carries the relative form). 0.4.5 was unaffected (inline
  `window.confirm`, no relative import).

- **Client mirror of #44: collections of *reactive* rows were STILL add-once-only in
  the browser — `#extractToken` read the FIRST token in the response, not this
  controller's own (#46).** The server fix in 0.4.2 (#44) made the `add` response
  correct — the container's fresh `reactive:token` stream is present — but the
  client still broke. After each action the reactive controller stores the
  response's fresh token for its NEXT dispatch; `#extractToken` did
  `html.match(/data-reactive-token-value="([^"]+)"/)` — the FIRST match in the whole
  body. On a collection of reactive rows the response is, in body order: the
  appended/prepended ROW (carrying its OWN token, since a reactive row is itself a
  `data-controller="reactive"` root) FIRST, then the container's `reactive:token`
  refresh LAST. So the list controller stored the ROW's token; its second dispatch
  sent a row token → failed verification → the second add silently did nothing. The
  fix reads the token that RE-RENDERS this controller's own element id — preferring
  the dedicated `reactive:token` stream targeting `this.element.id`, then a self
  `replace`/`update` of it — and otherwise keeps the existing token (never adopting
  a child row's or a sibling component's token). This is the exact client analogue
  of the #44 server rule: a stream "carries the token for C" only when it re-renders
  C itself, never when it inserts children into C. A request-level test can't catch
  this (the server response is already correct); covered by a bun unit test on the
  token selection AND a real two-click browser test (a collection of reactive rows →
  three rows after three adds) under Puma + Falcon. Refs cosmos#1939, #44, #30.

- **Collections of *reactive* rows were still add-once-only — a prepended/appended
  row's OWN token suppressed the container's token refresh (#44).** When an action
  appended/prepended a *reactive* child row into a container whose `#id` equals the
  append target (the most common collection shape — rows go directly into the
  container element), that single `append`/`prepend` stream carried BOTH
  `target="<container>"` and the row's own `data-reactive-token-value` (embedded in
  the `<template>`). `carries_token_for?` matched
  `include?("data-reactive-token-value") && include?(target)` in that one string →
  both true → it concluded the container's token was already fresh and **skipped**
  the container's `reactive:token` refresh. So the container (which owns the
  add/remove trigger) never rolled its token forward, and the second dispatch was
  rejected with the stale token — the list silently stopped after the first add.
  This hit both the hand-rolled `reply.streams(Row.prepend(...), …)` form **and**
  the `reactive_collection` / `reply.append`/`reply.prepend` helper, since they
  share the gate. Fixed by tightening `carries_token_for?`: a stream "carries the
  token for C" only when its action RE-RENDERS C itself (`replace`/`update`/
  `reactive:token` at C's target) — `append`/`prepend` (which insert *children*
  into C) never count, because a reactive child's token is not the container's. The
  idempotency the gate provided is preserved (a caller's own self-replace still
  suppresses the duplicate token) and the #30 sibling case still refreshes
  correctly. Covered at the request level: a reactive row appended twice in a row
  (the second using the token the first rolled forward) now succeeds, and each
  response carries a `reactive:token` stream targeting the container with a
  non-empty token. Refs cosmos#1939, #35, #30.

- **0.4.0 regression: re-renders lost the `request`, crashing `form_authenticity_token`
  and other request-dependent helpers (#42).** The 0.4.0 render-path perf rework
  built the cached off-request view context from a bare
  `ActionController::Base.new.view_context`, whose controller has `request == nil`.
  Any reactive component whose `view_template` calls `form_authenticity_token`,
  `protect_against_forgery?`, or a host-aware URL helper (all of which read
  `request.env`) then raised `NoMethodError: undefined method 'env' for nil` on
  **every** re-render — through the action endpoint AND on broadcasts — so any app
  with a reactive component rendering a Rails CSRF form could not adopt 0.4.0. Fixed
  by building the cached view context through a request-bound controller
  (`Phlex::Reactive.request_bound_view_context`), replicating exactly what
  `ActionController::Renderer#render` does to set up its mock request: an
  `ActionDispatch::Request` whose host is derived from the routes'
  `default_url_options`. The 0.4.0 `render_in` speedup is kept — the request is set
  up once when the per-thread context is built (not per render), and steady-state
  render throughput/allocations are unchanged (retained-per-render stays 0). Covered
  at the request level (a reactive `save` re-rendering a CSRF form returns 200, not
  500), the broadcast level (the form component broadcasts without crashing), and the
  unit level (a request is present on the cached context; host-aware `*_url` helpers
  resolve when the renderer carries routes).

- **Multipart path silently dropped an explicit nested-hash / array param (#39).**
  When an action declared a `:file` param alongside an explicit nested (hash/array)
  param, the nested param was dropped on the multipart path while the JSON path
  handled it correctly — the two encodings were asymmetric. The client's
  `#buildFormData` `JSON.stringify`'d a non-scalar param into one
  `params[key]='<json>'` field, which the server received as an un-decodable
  `String` leaf and dropped (nested hash → `{}`, array → key removed). Fixed
  client-side: `#buildFormData` now bracket-expands a nested object/array into
  `params[key][sub]` / `params[key][index][...]` fields (arrays use numeric
  indices) — the same Rails-form shape the server's `expand_bracket_keys` /
  `array_values` already parse, so a JSON body and a multipart body now coerce
  identically. The server is unchanged. One intentional divergence: an empty
  array/object as a whole param can't be carried by `FormData`, so the multipart
  path omits the key (the action's keyword default applies) rather than sending an
  explicit-clear `[]`/`{}`. Covered end-to-end: the bracketed multipart shape
  coerces correctly (request specs), a `:file` alongside a nested param both
  survive (request spec), and the FormData wire shape (bun unit tests).

- **`to_stream_token` emitted an EMPTY token, making non-self-rendering replies
  add-once-only (cosmos#1939).** `Streamable#to_stream_token` guarded on
  `respond_to?(:reactive_token)`, but `Component#reactive_token` is **private**, so
  the guard was false for every component and the refresh stream carried
  `data-reactive-token-value=""`. Any reply that opts out of the full-self replace
  but relies on the token-only refresh — `reply.streams` (#30) and the new
  `reply.append`/`reply.remove` (#35) — therefore rolled an empty token forward:
  the first action worked, then the next dispatch from that root was rejected (the
  stale/empty token fails verification) with no error. Fixed by checking private
  methods (`respond_to?(:reactive_token, true)`); a bare Streamable (genuinely no
  token) still skips correctly. The `reactive_collection` builders also now bind the
  **container** as the `token_component`, so an add/remove rolls the list root's
  token forward (the load-bearing part for repeated add/remove). Regression tests
  assert the token is non-empty AND re-verifies, and that a second add using the
  first reply's token succeeds.

### Changed

- **The browser suite now runs under two real servers — Puma and Falcon.** The
  `system` CI job runs as a matrix (`CAPYBARA_SERVER=puma` and `=falcon`), and a
  new `rake spec:system_servers` task runs both locally, so a reactive round trip
  is proven transport-agnostic across a sync (Puma, thread-pool) and an async
  (Falcon, fiber-per-request) server. `webrick` is **removed** as a test server
  (it isn't a real server) — `falcon` (with `protocol-rack`) replaces it as the
  alternative, registered via `Capybara.register_server(:falcon)`. No production
  dependency change; this is test infrastructure only.

- **CI now tests against Ruby 4.0** (added to the test matrix in `main.yml` and
  the pre-release matrix in `release.yml`, alongside 3.2/3.3/3.4; the lint and
  browser-system jobs also run on 4.0 now). Ruby 4.0 shipped December 2025 and is
  the current stable line. The gem requires no code changes for 4.0 — its
  dependencies and the patterns it uses (ObjectSpace::WeakMap, Data.define,
  Thread-locals, the MessageVerifier path) are stable across 3.4 → 4.0, and it
  directly requires none of the gems 4.0 moved from default to bundled.
  `required_ruby_version` stays `>= 3.2.0` (no upper bound, already permits 4.0).
  Verified empirically: the full unit/request/generator suite is green on Ruby
  4.0.5 with zero deprecation or unbundled-gem warnings.

### Added

- **`reactive_collection` — add/remove-row lists in one declaration (issue #35).**
  An add/remove-row list (line items, tags, comments, a notifications list) is one
  of the most common reactive surfaces, and every one re-implements the same
  orchestration by hand: append the row to the right container, remove it on
  delete, keep a count badge in sync, and swap an empty-state in/out as the list
  crosses 0↔1. `reactive_collection :items, item:, container:, count:, empty:,
  size:` declares that contract **once** on the container component, so each action
  is a single call: `reply.append(:items, model)` (row + count + empty-state
  clear), `reply.prepend(:items, model)`, and `reply.remove(:items, model_or_id)`
  (row + count + empty-state restore). The size badge and empty-state toggle are
  driven by the declared `size:` resolver, **re-counted server-side after the
  mutation** — so they're correct-by-construction (no off-by-one, no client-held
  count, consistent between the first render and the deltas). `count:`/`empty:`/
  `size:` are optional (omit them and only the row stream is emitted), and the new
  builders compose with `.flash`/`.stream` like any other reply. Reply governs the
  actor's HTTP response only; a cross-tab live list still broadcasts the row with
  `broadcast_append_to(..., exclude: reactive_connection_id)`. New
  `Phlex::Reactive::Component::CollectionDefinition`,
  `reactive_collection`/`reactive_collection_def`/`reactive_collection?` macros,
  and `Response.collection_append`/`collection_prepend`/`collection_remove` behind
  the `reply.*` surface.

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
