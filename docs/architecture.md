---
layout: default
title: Architecture
nav_order: 3
---

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
c.to_stream_remove            → <turbo-stream action="remove" target="<c.id>">    (backs reply.remove)
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

The endpoint verifies the token, rebuilds the component, and runs the action. If
the action returns [`reply.<verb>`](../README.md#reply--controlling-the-actions-reply)
(a replace/update, a remove, a redirect, or multiple streams — optionally with a
flash), the endpoint renders that; otherwise it falls back to the implicit single
`component.to_stream_replace` (the legacy contract). For any non-remove/redirect
reply the component's own replace is guaranteed present so its token refreshes.
Turbo applies it in: a plain `replace` is an outerHTML swap; `reply.morph`
(or `reply.update`) morphs the subtree in place, preserving the focused input +
caret for per-field editing (issue #28).

`reply.<verb>` returns a `Phlex::Reactive::Response` — the immutable value object
the endpoint reads (`response_streams`). It's an internal detail; you build it
through `reply`.

### What collected fields are

On a button click or form submit, the controller auto-collects named fields
inside the component so the action receives them without you wiring anything:

- **Standard controls** — `input[name]`, `select[name]`, `textarea[name]`
  (checkboxes send their `checked` state; radios send the checked value).
- **Rich-text / custom editors** — named `lexxy-editor`, `trix-editor`, and
  `[contenteditable]` elements with a `name` attribute (the editable ones:
  `contenteditable`, `="true"`, or `="plaintext-only"` — an explicit
  `contenteditable="false"` is skipped). These aren't standard controls, so
  they're read explicitly (serialized `.value`, else the contenteditable text).
  Without this a reactive save would post an empty value and silently wipe the
  field.

Only fields that exist in the DOM are sent; a declared param with no matching
field is simply absent (the action's keyword default applies). Explicit params
from `on(:save, extra: ...)` always win over a collected field of the same name.

> A rich editor that mirrors its value into a hidden `input[name]` (e.g. Trix)
> is already covered by the standard query; the editor read only fills a name
> the standard controls left absent or empty, so it never clobbers a populated
> input.

#### Nested reactive roots collect independently

A reactive component can be rendered **inside** another — each `**reactive_attrs`
root is its own `data-controller="reactive"` element. Field collection stops at
nested roots: an action collects only the named inputs whose nearest
`[data-controller~="reactive"]` ancestor is *its own* root. A descendant
reactive component's inputs belong to that component, not the outer one.

```ruby
# Outer editor (its own root) containing N reactive line-item rows (each a root).
class InvoiceEditor < ApplicationComponent
  # ... reactive_record :invoice; action :save, params: { notes: :string }
  def view_template
    div(id:, **reactive_attrs) do
      input(name: "notes", value: @invoice.notes)              # collected by `save`
      @invoice.items.each { |item| render LineItem.new(item:) } # each row is its own root
      button(**on(:save)) { "Save" }
    end
  end
end
```

A `save` on the editor receives `{ notes: }` only — never the rows' bare
`quantity`/`price` inputs. A `quantity` change inside a row dispatches on *that
row's* controller and updates only that row. So outer flat fields and per-row
reactive editing compose without name-collision workarounds (issue #15).

> Remember `mix` when a nested root needs its own `id`/`data`:
> `div(**mix(reactive_attrs, id:, data: { testid: "row" }))`. A bare
> `div(id:, **reactive_attrs, data: {...})` lets the extra `data:` clobber
> `reactive_attrs`' `data-controller`, so the element never becomes a root.

## Why state isn't in the browser

Livewire ships a *snapshot* of component state to the client and trusts it back
(with a checksum). That's an attacker-controlled mass-assignment surface and
forces a re-signing protocol for two-way binding. We don't do that.

Instead the DOM carries a **signed identity**:

- **Record-backed**: `{ c: "Todos::Item", gid: "gid://app/Todo/42" }`. The
  server re-finds the record from the database. State = the DB. The client can't
  forge the class or swap the record (signature), and can't see or change the
  record's columns (they're never in the token).
- **State-backed**: `{ c: "Counter", s: { count: 3 } }`. For record-less
  widgets. The state is signed, so the client can't tamper with it, but keep it
  small and non-sensitive.
- **Record + state**: `{ c: "Fields::InlineEdit", gid: "gid://app/User/7", s: { attribute: "name", editing: true } }`.
  When a component declares both `reactive_record` and `reactive_state`, the
  record's GlobalID **and** the declared state are signed into one token and
  both are restored on each action — so transient mode (which field, edit/show)
  is tamper-proof alongside the record. See the
  [inline edit example](examples/inline_edit.md).

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

### Debounced triggers

A trigger may opt into a quiet-period debounce with
`on(:update, event: "input", debounce: 300)`. The controller reads the debounce
(a Stimulus `data-reactive-debounce-param`) in `dispatch` and, instead of
enqueuing the round trip immediately, resets a **per-trigger-element** timer;
only after `debounce` ms of quiet does it enqueue onto the same per-component
queue (so token threading still holds). A `blur` on the element flushes a pending
dispatch immediately, so tabbing away never drops the last edit. `preventDefault`
still fires synchronously, so a debounced `submit` trigger won't navigate
(issue #11). On `disconnect` (the element leaves the DOM via a Turbo morph or
navigation) every pending debounce timer is cleared, so a deferred round trip
never fires against a detached controller. Without `debounce:`, dispatch is
immediate — unchanged behavior.

Result: type `c-a-t-s` fast into a debounced input → ONE search round trip, not
four.

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
