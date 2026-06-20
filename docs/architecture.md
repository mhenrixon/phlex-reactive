# Architecture & mental model

phlex-reactive is small. Understanding it fully takes five minutes.

## The one idea

> A component owns a stable DOM `id`. Everything — a click, a form change, a
> background broadcast — reduces to **"render this component into that id."**

Client interactivity and server-pushed live updates are the *same operation*,
which is why the library is so small: there's only one re-render unit and one way
to target it.

## The two halves

### Server → client: `Streamable`

A component that implements `#id` can render itself as a Turbo Stream:

```
Counter.replace(c)            → <turbo-stream action="replace" target="<c.id>">…</turbo-stream>
Counter.broadcast_replace_to(stream, model: c)  → same, pushed over the transport
```

Rendering goes through a real controller renderer (`Phlex::Reactive.renderer`),
so `dom_id`, `url_for`, `t()`, CSRF, etc. work during a re-render or broadcast.
This is deliberate: re-rendering a component without a view context is the #1
footgun in server-driven UIs, and we avoid it by always rendering through the
controller.

### Client → server: `Component`

A component declares actions and emits, on its root element:

```html
<div id="counter"
     data-controller="reactive"
     data-reactive-token-value="<signed { c, gid|state }>">
  <button type="button"
          data-action="click->reactive#dispatch"
          data-reactive-action-param="increment"
          data-reactive-params-param="{}">+</button>
</div>
```

The generic `reactive` Stimulus controller turns a click into:

```
POST /reactive/actions
{ "token": "<signed>", "act": "increment", "params": { ...collected fields... } }
Accept: text/vnd.turbo-stream.html
```

The endpoint verifies the token, rebuilds the component, runs the action, and
returns `component.to_stream_replace`. Turbo morphs it in.

## Why state isn't in the browser

Livewire ships a *snapshot* of component state to the client and trusts it back
(with a checksum). That's an attacker-controlled mass-assignment surface and
forces a re-signing protocol for two-way binding. We don't do that.

Instead the DOM carries a **signed identity**:

- **Record-backed**: `{ c: "Todos::Item", gid: "gid://app/Todo/42" }`. The
  server re-finds the record from the database. State = the DB. The client can't
  forge the class or swap the record (signature), and can't see or change the
  record's columns (they're never in the token).
- **State-backed**: `{ c: "Counter", s: { count: 3 } }`. For genuinely
  record-less widgets. The state is signed, so the client can't tamper with it,
  but keep it small and non-sensitive.

The token is a Rails `MessageVerifier` token bound to the purpose
`"phlex-reactive/identity"`.

## The re-render is whole-component, and that's fine

We re-render and replace the *entire* component, then let **idiomorph** (Turbo 8
morphing) patch only what actually changed in the DOM — preserving focus, scroll,
and unchanged nodes. We do **not** compute server-side diffs or maintain a
template AST (Phlex has neither, and doesn't need them). For the vast majority of
components, "render the component, morph it in" is the right trade: tiny code,
no stale-cache hazards, payload bounded to one component.

If a single component grows large and chatty, split it into smaller components
and broadcast the inner one. That's the idiomatic answer, not a diff engine.

## Concurrency: the in-flight token race

Because state lives in the token and the token is rewritten by each response, two
requests in flight at once would both read the *old* token and clobber each other
(last-write-wins). The client runtime prevents this two ways:

1. **Per-component queue** — `dispatch` chains on a per-controller promise, so
   requests for one component run one at a time.
2. **Synchronous token threading** — each response's new token is parsed out of
   the returned HTML immediately and used for the next queued request, without
   waiting for the async DOM morph.

Result: click `+` five times fast → `5`, never `1` or `2`.

## What runs where

| Concern | Where |
|---|---|
| Action declarations, identity signing, re-render | Ruby (`Component`, `Streamable`) |
| Token verification, record re-find, action dispatch, param coercion | `ActionsController` |
| Event binding, request serialization, token threading, morph | One Stimulus controller (~150 LOC) |
| Transport (SSE/Action Cable), reliability, presence | pgbus / turbo-rails |
| DOM patching | idiomorph (via Turbo) |

## What we deliberately did NOT build

- **No template AST / parser.** Phlex compiles to a string buffer; we don't need
  template structure to know what to re-render — the component *is* the unit.
- **No stateful process per client** (the LiveView model). The server stays
  stateless; identity travels in the signed token. Scales like any Rails request.
- **No client state snapshot.** State is the DB behind a signed identity.
- **No bespoke transport or big client framework.** Turbo + idiomorph already
  morph; pgbus already delivers. We add ~150 lines of glue, not a framework.
