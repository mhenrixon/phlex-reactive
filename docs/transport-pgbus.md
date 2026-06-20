---
title: Transport (pgbus)
nav_order: 6
---

# Transport: pgbus vs Action Cable

phlex-reactive's *client → server* half is a plain HTTP POST — nothing special.
The *server → client* half (broadcasts) rides on whatever transport turbo-rails
is configured with. You have two choices.

## Action Cable (default turbo-rails)

Works out of the box. `broadcast_*_to` and `turbo_stream_from` go over WebSocket
via Action Cable, which needs a Redis (or solid_cable) backend. Known rough
edges:

- **Page-born-stale**: a broadcast that fires between server render and client
  subscribe is lost.
- **Lost on reconnect**: messages sent while a tab was briefly disconnected are
  gone.
- **No transactional safety**: a broadcast inside a rolled-back transaction may
  still fire (depending on where you put it).

## pgbus (recommended)

[pgbus](https://github.com/mhenrixon/pgbus) replaces the transport with
PostgreSQL SSE and fixes all three. Install it and broadcasts route over pgbus
automatically — `broadcast_*_to` and `turbo_stream_from` are patched, so
**phlex-reactive code is identical.** You just get:

- **Transactional broadcasts** — deferred to `after_commit`; a rolled-back
  transaction emits nothing.
- **Reconnect-safe** — the client persists a cursor (`Last-Event-ID`) and
  replays missed messages from the PGMQ archive.
- **No render→subscribe race** — broadcasts are watermarked and replayed.
- **Connection-state DOM events** — `pgbus:open`, `pgbus:gap-detected`,
  `pgbus:close` on the `<pgbus-stream-source>` element.
- **No Redis, no Action Cable.** One Postgres.

### Setup

```ruby
# Gemfile
gem "pgbus"
gem "phlex-reactive"
```

```erb
<%# subscribe — pgbus patches turbo_stream_from to render <pgbus-stream-source> %>
<%= turbo_stream_from @room, :messages %>
```

```ruby
# durable streams replay on reconnect:
class Message < ApplicationRecord
  broadcasts_to ->(m) { [m.room, :messages] }, durable: true
end
```

### Durability

`durable: true` persists broadcasts in PGMQ so a disconnected client replays them
on reconnect. Use it for anything where missing one update strands the UI (chat,
order/checkout status, AI replies). Leave it ephemeral for high-frequency,
low-stakes updates (presence pings, typing indicators) to keep the archive small.

## How a broadcast reaches the browser (pgbus)

```
Component.broadcast_replace_to(stream)            (your code)
  → Turbo::StreamsChannel.broadcast_replace_to    (patched by pgbus)
  → Pgbus.stream(key).broadcast(html)             (deferred to after_commit)
  → PGMQ row + LISTEN/NOTIFY wake-up
  → /pgbus/streams/<signed> SSE endpoint streams: event:message data:<turbo-stream>
  → <pgbus-stream-source> forwards to Turbo's StreamObserver
  → idiomorph morphs the component into the DOM by its id
```

The wire format is an ordinary `<turbo-stream>` — pgbus is a drop-in transport,
not a new protocol. That's why switching transports requires zero changes to
phlex-reactive components.

## Choosing

| You have / want | Use |
|---|---|
| Already on Action Cable, low reliability needs | Action Cable (default) |
| Postgres, want no Redis, want reliability | **pgbus** |
| Transactional UI correctness (status flows, payments) | **pgbus** (durable) |
| Reconnect-safe chat / live feeds | **pgbus** (durable) |

## Roadmap

A few pgbus enhancements would make reactive UX even smoother — tracked as
issues on pgbus (e.g. per-connection actor-echo suppression, render-and-
broadcast, optimistic-UI revision stamping, connection-driven presence). See
[mhenrixon/pgbus issues labelled `streaming`](https://github.com/mhenrixon/pgbus/issues?q=is%3Aissue+label%3Astreaming).
