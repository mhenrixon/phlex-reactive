# #165 — Deferred reply segments (`reply.defer`) + lazy initial mount

Status: implemented · Branch: `issue-165-deferred-reply-segments`

## As built (deltas from the plan below)

- **Measured (same-checkout `git switch --detach` before/after; a fresh
  worktree gives phantom deltas from dummy tmp/secret state):** hot paths flat
  — `to_stream_replace` 14.4k → 14.2k i/s (±3.7% noise), identity token
  199.9k → 196.7k (state) / 93.7k → 93.5k (record), allocations byte-identical.
  New defer costs are per-interaction, not per-render: `sign_defer` ~120k i/s,
  `verify_defer` ~99k i/s, directive build ~11 µs, 0 retained
  (`benchmark/micro/defer_token.rb`). The A/B request spec pins the latency
  shape: a 120 ms segment cost moves off the reply onto the deferred leg.
- **Lazy mount is pull-only** (as planned): the shell carries the defer token
  on the ROOT; the controller's `connect()` probes it. The token attribute
  stays on the shell so a Turbo cache restoration re-fires the fetch.
- **Real-render semantics sharpened:** `reactive_lazy` shells render ONLY on
  page-embedded mounts. Everything through `Streamable.render_component` /
  `Phlex::Reactive.render` runs inside `Defer.with_real_render` — an action's
  self-replace, broadcasts, and the defer endpoint/job all emit the real
  template (no double round trips, no shell echo).
- **Push-lane degrade hardened:** a signing/enqueue failure AFTER commit falls
  back to the fetch directive with a warn (a committed action's reply must
  never 500); gone-record / `render?`-false jobs broadcast a cleanup
  (reactive:js pending-clear ops + source teardown) so the shimmer never hangs.
- **Doctor** gained a `defer_route` check (the issue-#26 catch-all shadow
  class); the boot-time warn stays scoped to `action_path` (the doctor names
  the defer variant).
- **LogSubscriber** logs `defer.phlex_reactive`; the install initializer
  template documents `defer_transport` / `defer_token_ttl` / `defer_job_queue`
  / `defer_path`.

## Problem

Every reply segment renders synchronously on the request thread; one expensive
segment (a cross-aggregate rollup) stalls the actor's whole interaction. #165
wants "placeholder now, real HTML to the actor when ready" — actor-scoped,
superseding, transactional. Docs must lead with **profile first**: an app-side
N+1 looks like framework lag (the reps-totals story).

## Decisions (user-confirmed)

1. **Full hybrid delivery** — a pull engine that works everywhere + a
   pgbus-durable push lane behind a capability gate, selected by
   `Phlex::Reactive.defer_transport = :auto | :fetch | :stream` (default
   `:auto` → push iff pgbus durable Streams + ActiveJob are present, else pull).
   Forced `:stream` without capability → warn + pull fallback (degrade, never
   break).
2. **Pending-state default: keep current content** + `data-reactive-defer-pending`
   / `aria-busy` markers (CSS shimmer hook). `placeholder:` opts into a skeleton
   that replaces the target immediately.
3. **Also ship lazy initial mount** (Livewire `#[Lazy]`-style): first page render
   emits the placeholder shell; content arrives via the same defer machinery.
   Lazy mount is **pull-only** in this PR (a page render has no transaction to
   defer behind and job-enqueue-during-render couples rendering to queue infra;
   the push lane can adopt it later if measurement asks for it).

## Developer API (identical on both lanes)

```ruby
action :update, params: { weight_kg: :float, reps: :integer, rpe: :float }
def update(weight_kg:, reps:, rpe:)
  authorize! @set, :update?
  @set.update!(weight_kg:, reps:, rpe:)
  reply
    .streams(volume_cell_stream)                  # cheap — instant
    .defer(SessionTotals.new(workout: @workout))  # expensive — off the critical path
end

reply.defer(comp)                          # keep stale content, mark pending
reply.defer(comp, placeholder: true)       # comp's deferred_placeholder / built-in shell
reply.defer(comp, placeholder: Skeleton.new) # explicit skeleton (component or String)
reply.defer(comp, morph: true)             # arrival morphs instead of replaces
```

Lazy mount:

```ruby
class SessionTotals < ApplicationComponent
  include Phlex::Reactive::Component
  reactive_record :workout
  reactive_lazy                    # first render = placeholder shell + defer fetch

  def deferred_placeholder = div(class: "skeleton h-24")  # optional override
end
```

Config: `Phlex::Reactive.defer_transport`, `.defer_token_ttl` (default 120s),
`.defer_path` (default "/reactive/defer").

## Wire format

Directive (rides the reply, which renders only **after commit** — transactional
by construction; a rollback takes the rescue path and no directive is emitted):

```html
<!-- pull -->
<turbo-stream action="reactive:defer" target="session_totals"
  data-reactive-defer-via="fetch"
  data-reactive-defer-token="<signed {c, gid|s, m}, purpose phlex-reactive/defer, TTL 120s>">
</turbo-stream>

<!-- push (pgbus durable lane only) -->
<turbo-stream action="reactive:defer" target="session_totals"
  data-reactive-defer-via="stream"
  data-reactive-defer-src="<pgbus-signed one-shot SSE url>"
  data-reactive-defer-since-id="0"></turbo-stream>
```

Push-lane contract (verified against the pgbus checkout):

- One-shot key: `prdefer_<SecureRandom.hex(16)>` — 40 chars, `[a-zA-Z0-9_]` only.
  pgbus's queue-name budget is 47 − prefix("pgbus") − 1 = **41 chars**, pattern
  `[a-zA-Z0-9_]+` (hyphens are *stripped* by the sanitizer, so never use them)
  — `pgbus/lib/pgbus/queue_name_validator.rb:24,27`, `streams/key.rb:184-187`.
- src minting (no view context needed):
  `Pgbus::Streams::SignedName.sign(key)` +
  `Pgbus.configuration.streams_path || Pgbus::Engine.routes.url_helpers.streams_path`
  (rescue NameError → `"/pgbus/streams"`), then `"#{base}/#{signed}"` —
  `pgbus/app/helpers/pgbus/streams_helper.rb:32-54,103-111`.
- Job broadcast MUST be durable for the since-id replay to close the
  subscribe race: `Pgbus.stream(key, durable: true).broadcast(html)` where
  `html` = the replace stream + a remove of `#reactive-defer-src-<target>`
  (self-tearing subscription). Ephemeral broadcasts are NOT replayable —
  `pgbus/lib/pgbus/streams.rb:129,147-166`, `client/read_after.rb:114-134`.
- `<pgbus-stream-source src=… since-id="0">` is the minimal element; since-id 0
  on a fresh key replays the entire (one-message) backlog even when the
  broadcast beat the subscription; `disconnectedCallback` tears the SSE down —
  `pgbus/app/assets/javascripts/pgbus/stream_source_element.js:82-105,345-352`.

`placeholder:` additionally emits a normal replace stream BEFORE the directive:
a shell `<div id="<target>" data-reactive-defer-pending aria-busy="true">` that
wraps the placeholder HTML (the shell owns the id so any placeholder works).

Lazy mount carries the directive as ROOT attributes instead of a stream:
`data-reactive-defer-token` on the shell root; the controller's `connect()`
probes it (same gated-probe pattern as dirty tracking) and enters the same
fetch path.

## Client machinery (module-level, OFF the per-controller action queue)

```js
const pendingDefers = new Map() // targetId -> { via, abort? , srcEl? }
```

- `reactive:defer` handler: supersede an existing entry for the target (abort
  fetch / remove old source element), mark pending, then:
  - `via=fetch`: parallel `POST defer_path {token}`; on arrival, apply only if
    still current (registry check) then `renderStreamMessage` — the fresh root
    clears the pending marker naturally. Timeout + error → clear marker, set
    `data-reactive-error="defer"`, console.error.
  - `via=stream`: insert `<pgbus-stream-source id="reactive-defer-src-<target>"
    src=… since-id=…>`; the job's broadcast carries `[replace <target>,
    remove #reactive-defer-src-<target>]`, so arrival + teardown need no custom
    client logic. Guard: unregistered custom element → console.error + no-op.
- Supersession: newer directive for the same target wins; the aborted fetch /
  unsubscribed one-shot stream can never paint stale content.

## Server pieces

| Piece | File |
|---|---|
| `Response#defer` + `deferred_segments` (frozen `DeferSegment` data) | `lib/phlex/reactive/response.rb` |
| `Reply#defer` pass-through | `lib/phlex/reactive/reply.rb` |
| Defer builder: lane resolution, directive + placeholder streams, token mint | `lib/phlex/reactive/defer.rb` |
| `sign_defer`/`verify_defer` (purpose `phlex-reactive/defer`, `expires_in:`), config, capability gates `pgbus?` / `pgbus_streams?` (new — documented in CLAUDE.md but not yet implemented) | `lib/phlex/reactive.rb` |
| Endpoint: `deferred` action (verify → `from_identity` → render), defer streams appended post-commit in `response_streams`, push-lane enqueue | `app/controllers/phlex/reactive/actions_controller.rb` |
| Push job (ActiveJob-guarded) | `app/jobs/phlex/reactive/deferred_render_job.rb` |
| `reactive_lazy` DSL + `around_template` interception | `lib/phlex/reactive/component/dsl.rb` / new module |
| Route `post defer_path` | `lib/phlex/reactive/engine.rb` |

Security: defer token is purpose-scoped (an action token is rejected at the
defer endpoint and vice versa), short-TTL, tamper-fails-closed through the
existing `InvalidToken` path. The signature proves identity, not permission —
auth comes from `base_controller_name` (same contract as actions);
`component.render?` false → 204 (clear pending, keep content). A deferred
render's HTML carries a fresh action token, so the component lands interactive.

## Measurement (the honest definition)

Two metrics, both reported: **actor reply latency** (better with defer) and
**time-to-full-content** (slightly worse: +1 hop). Deliverables:

1. Request-level A/B spec: deliberately slow component (~120ms render); sync
   `also_replace` reply pays ~base+120ms, `.defer` reply returns in ~base.
2. `rake bench` before/after vs main — the non-defer endpoint path must not
   regress; new micro-bench for defer-token sign+verify.
3. Browser suite (Puma + Falcon): pending marker appears immediately, content
   streams in, typing during the pending window still dispatches (queue
   unblocked), rapid actions → no stale paint (supersession), lazy mount
   placeholder → content.

## Test matrix

- Unit: Response#defer/Reply#defer, Defer builder (both lanes), token
  purpose/TTL/tamper, gates (pgbus absent / present / old-shape double),
  reactive_lazy render interception.
- Request: defer endpoint (200/400 purpose-confusion/400 expired/404/403
  base-controller), directive emission, rollback → no directive, push-lane
  enqueue (ActiveJob test adapter) + old-pgbus-shape regression.
- JS (bun): handler registration, parallel fetch off the queue, supersession
  abort, error/timeout marker, stream-lane element insertion + guard.
- System: defer_spec (marker → content, no reload, supersession), lazy mount,
  placeholder skeleton variant.
