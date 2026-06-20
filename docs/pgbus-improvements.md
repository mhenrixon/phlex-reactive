# pgbus improvements that would make phlex-reactive even better

A prioritized, concrete proposal for pgbus enhancements that directly improve the
reactive experience. Each item notes what already exists in pgbus today (it has a
lot — presence, audience filters, cursor replay, rich client events) so nothing
is reinvented.

Legend: **★ high impact** · ◐ medium · ○ nice-to-have.

---

## ★ 1. Per-connection actor-echo suppression (`exclude:` on broadcast)

**Problem.** When a user triggers a reactive action that broadcasts (e.g. "send
message"), they receive both (a) the action's HTTP response AND (b) the SSE echo
of their own broadcast. Today we lean on idiomorph DOM-id dedup to swallow the
duplicate. That works for `append`/`replace` of an element with a stable id, but
it's fragile for: ordered inserts, optimistic UI, animations (the echo re-runs
them), and any non-idempotent action.

**What pgbus already has.** `Pgbus::Streams::Filters` — per-connection,
server-side audience predicates evaluated against each connection's
authorize-context (`visible_to: :label`). The delivery-time, per-connection
filtering machinery is *already there*.

**Proposal.** Give every SSE connection a stable **connection id** (pgbus can
mint one and expose it to the page, e.g. via a `<meta name="pgbus-connection-id">`
or on the `<pgbus-stream-source>` element). Let a broadcast carry an
`exclude:`/`origin:` connection id; the dispatcher skips delivery to that
connection — reusing the Filters delivery path.

```ruby
# phlex-reactive would pass the actor's connection id (sent in the action POST):
Chat::Message.broadcast_append_to("chat", room, target:, model: msg,
                                  exclude: request.headers["X-Pgbus-Connection"])
```

**Why it's the #1 ask.** It removes the single sharpest correctness edge in
server-driven UIs (double-apply), makes optimistic UI safe, and unlocks "the
actor's truth is the HTTP response; everyone else gets the broadcast" — the clean
Livewire model. The hook (`exclude` → Filters-style skip) is small given what
exists.

---

## ★ 2. A first-class "render-and-broadcast a Phlex component" entry point

**Problem.** Today phlex-reactive renders the component to HTML
(`ApplicationController.render`) and hands the string to
`Turbo::StreamsChannel.broadcast_*_to`. That's two concerns stitched together,
and the render needs a view context that's easy to get wrong off-request.

**Proposal.** A pgbus stream method that accepts a *renderable* + a Turbo action
+ target and does the render (with a correct, reusable view context) and the
broadcast atomically:

```ruby
Pgbus.stream("chat", room).broadcast_render(
  renderable: Chat::Message.new(chat_message: msg),
  action: :append, target: "chat-messages-#{room}",
  exclude: connection_id     # ties in with #1
)
```

**Why.** Centralizes the off-request view-context construction (the documented #1
footgun) in pgbus, so every gem/app broadcasting a component gets it right.
phlex-reactive's `Streamable.broadcast_*_to` becomes a thin shim over this.

---

## ◐ 3. Stream-key helper that accepts an already-built key (idempotent keying)

**Problem.** `broadcast_*_to(*streamables)` builds the key internally via
`Pgbus.stream_key(*streamables)`. Passing an already-built key (`"chat:lobby"`)
trips the colon separator guard with an `ArgumentError`. This bit us during
development and is a sharp edge for anyone who has a `stream_key` helper they pass
to both `turbo_stream_from` and the broadcaster.

**Proposal.** Make `Pgbus.stream_key` **idempotent**: if given a single argument
that is already a well-formed pgbus stream key (matches the built format), return
it unchanged instead of re-keying and raising. Or add `Pgbus.stream_key!(key)`
that accepts a pre-built key. Either makes "use the same key on both sides"
foolproof.

**Why.** Removes a confusing, easy-to-hit error. Pure ergonomics, no behavior
change for the common path.

---

## ◐ 4. Optimistic-update acknowledgement / revision stamping

**Problem.** Optimistic UI (apply the change locally before the server confirms)
needs a way to reconcile: when the authoritative broadcast/response arrives, the
client must know whether it supersedes the optimistic state. Without a monotonic
marker, a late echo can overwrite a newer optimistic edit.

**What pgbus already has.** Monotonic `msg_id` per stream message (used for
`Last-Event-ID` replay). The ordering primitive exists.

**Proposal.** Expose the message's `msg_id` (or a per-target revision) to the
client on each delivered frame as a data attribute / event detail, and document a
"skip morph if I've already applied a newer rev for this target" pattern. pgbus
emits the rev; phlex-reactive's runtime consumes it.

**Why.** Makes safe optimistic UI possible without a bespoke versioning scheme.
Complements #1 (exclude handles the actor; rev handles out-of-order for everyone).

---

## ◐ 5. Connection-driven presence (auto join/leave)

**Problem.** pgbus presence is excellent but **v1 is explicit** — the app must
call `join`/`leave`/`touch` and run a sweeper. For "who's online / who's typing"
in a reactive component, wiring lifecycle by hand is friction.

**What pgbus already has.** Full `Presence` (join/leave/touch/members/count/
sweep!) backed by `pgbus_presence_members`, and client connection events
(`pgbus:open`/`pgbus:close`).

**Proposal.** Auto-join on SSE connect and auto-leave on disconnect, driven by
the connection lifecycle + the authorize-context's member id, with the heartbeat
(`touch`) on the existing keepalive. Make it opt-in per stream
(`presence: true`). The app provides identity + metadata via the authorize hook;
pgbus manages membership.

**Why.** Turns presence from a manual integration into a one-flag feature —
exactly the DX phlex-reactive aims for. Then a `<Presence>` Phlex component is
trivial.

---

## ○ 6. Typed SSE events for reactive frames (beyond `event: message`)

**Problem.** Everything arrives as a Turbo Stream on the default `message` event.
That's great for interop but means the client can't cheaply distinguish, say, a
"presence" frame from a "content" frame without parsing the HTML.

**Proposal.** Allow a broadcast to set an SSE `event:` name (e.g.
`event: presence`, `event: reactive`) while keeping the payload a Turbo Stream.
Clients that care can listen for the typed event; default consumers still get
`message`. Keep it optional so the drop-in Turbo path is unchanged.

**Why.** Enables lightweight client-side routing (analytics, presence pills,
sound on new message) without HTML sniffing. Low priority because the HTML-only
path already works.

---

## ○ 7. Rate limiting / coalescing for high-frequency reactive streams

**Problem.** A chatty reactive component (live cursor, typing, progress bar) can
fan out many small broadcasts. For per-keystroke or per-frame updates that's
wasteful.

**Proposal.** Optional server-side coalescing per (stream, target): within a
short window, keep only the latest frame for a target before delivery
(last-write-wins for "replace"/"update" actions, which are idempotent). Opt-in via
`coalesce: true` or a window.

**Why.** Lets reactive components be used for high-frequency UI (progress,
presence, cursors) without flooding the bus. Lower priority — most reactive UI is
event-driven, not frame-driven.

---

## Summary table

| # | Improvement | Impact | Builds on existing pgbus | Effort |
|---|---|---|---|---|
| 1 | Actor-echo suppression (`exclude:`) | ★ | Filters delivery path | small–med |
| 2 | `broadcast_render(renderable:, action:, target:)` | ★ | stream broadcast + render | med |
| 3 | Idempotent `stream_key` for pre-built keys | ◐ | Key builder | small |
| 4 | Revision stamping for optimistic UI | ◐ | `msg_id` ordering | small–med |
| 5 | Connection-driven presence (auto join/leave) | ◐ | Presence + conn events | med |
| 6 | Typed SSE `event:` names | ○ | SSE framing | small |
| 7 | High-frequency coalescing | ○ | Dispatcher | med |

**If only one ships: #1 (actor-echo suppression).** It's the difference between
"works because idiomorph happens to dedup" and "correct by construction," and it
unlocks safe optimistic UI. The Filters machinery means pgbus is already 80% of
the way there.
