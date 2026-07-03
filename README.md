# phlex-reactive

[![CI](https://github.com/mhenrixon/phlex-reactive/actions/workflows/main.yml/badge.svg)](https://github.com/mhenrixon/phlex-reactive/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/phlex-reactive)](https://rubygems.org/gems/phlex-reactive)
[![Docs](https://img.shields.io/badge/docs-phlex--reactive.zoolutions.llc-blue)](https://phlex-reactive.zoolutions.llc)

**Reactive [Phlex](https://www.phlex.fun) components for Rails — Livewire-style
actions and live cross-tab updates, without writing Stimulus controllers or
hand-picking Turbo Stream targets.**

📖 **[Full documentation](https://phlex-reactive.zoolutions.llc)**

```ruby
class Counter < ApplicationComponent
  include Phlex::Reactive::Component   # pulls in Streamable too

  reactive_state :count
  action :increment
  action :decrement

  def initialize(count: 0) = @count = count
  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1

  def view_template
    div(**reactive_root) do
      button(**on(:decrement)) { "−" }
      span { @count }
      button(**on(:increment)) { "+" }
    end
  end
end
```

That's the whole counter. **No Stimulus controller. No `.turbo_stream.erb`. No
route. No hand-picked target.** Click `+` and the count updates in place.

---

## Why

Stimulus + Turbo are powerful but tedious. A single interactive widget means a
Stimulus controller, a `data-*` soup, a `.turbo_stream.erb` view, a controller
action, and a hand-picked `dom_id` target — repeated for every feature. The
mental model is "wire everything by hand."

phlex-reactive borrows the **mental model** that makes Livewire and Phoenix
LiveView pleasant — *a component has state and actions; change state and the UI
follows* — and implements it the Rails way:

- **Actions are Ruby methods.** Declare `action :increment`; the client calls it.
- **Re-render is auto-targeted.** A component owns a stable `id`; the response is
  a `<turbo-stream>` that replaces it. You never pick a target.
- **The same unit re-renders for clicks AND broadcasts.** A click and a
  background broadcast both produce "replace the component by its id," so live
  cross-tab updates are the same mechanism as local interactivity.
- **State lives in your database, not the browser.** The DOM carries only a
  *signed identity* (a record's GlobalID), not a snapshot of state — so there's
  no mass-assignment surface and no re-signing protocol.
- **One tiny client runtime.** A single generic Stimulus controller, registered
  once, handles every reactive component. You don't write per-feature JS.

Pair it with [**pgbus**](https://github.com/mhenrixon/pgbus) and your live
updates become *transactional* (no broadcast for a rolled-back change) and
*reconnect-safe* (missed messages replay) over Postgres SSE — **no Action Cable,
no Redis.**

---

## Installation

```ruby
# Gemfile
gem "phlex-reactive"
```

```bash
bundle install
```

Then run the installer — it registers the client controller and writes a config
initializer:

```bash
bin/rails generate phlex:reactive:install
```

That's all for **importmap** apps: the engine mounts the action endpoint at
`/reactive/actions` and auto-pins (and preloads) the client runtime, and the
installer adds the eager registration below to your Stimulus entrypoint.

<details>
<summary>What the installer wires (or do it by hand)</summary>

```js
// app/javascript/controllers/index.js
import { application } from "controllers/application"
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

Register eagerly (not lazily) so a click immediately after load is never missed.
</details>

### Scaffold a component

```bash
# state-backed (record-less)
bin/rails generate phlex:reactive:component Counter increment decrement

# record-backed (signed GlobalID identity)
bin/rails generate phlex:reactive:component Todos::Item toggle rename --record todo
```

Generates the component (and an RSpec spec if your app uses RSpec).

<details>
<summary>esbuild / webpack / bun</summary>

Import and register it from your controllers entrypoint:

```js
import { application } from "./application"
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

The JS ships at `app/javascript/phlex/reactive/reactive_controller.js` in the
gem; point your bundler at the gem path or copy it in. See
[docs/installation.md](https://phlex-reactive.zoolutions.llc/docs/installation).
</details>

**Requirements:** Rails 7.1+, Phlex 2 (`phlex-rails`), Turbo 8+ (for morphing),
and a Phlex `ApplicationComponent` base class. pgbus is optional but recommended
for broadcasting.

### Integration troubleshooting (silent "nothing happens")

Two host-app setups make the first reactive component *silently do nothing* —
components render, but no action ever fires, with no error pointing at the cause.
The gem now logs a warning for each, but here are the fixes:

**A catch-all route shadows `POST /reactive/actions`.** The engine appends its
route *after* everything in your `config/routes.rb`, so a bottom-of-file
catch-all wins and every reactive POST 404s:

```ruby
# config/routes.rb — a catch-all like this shadows the engine's appended route
match "*path", to: "errors#not_found", via: :all
```

Exempt the reactive path from the catch-all (or set
`Phlex::Reactive.action_path` to an unshadowed path):

```ruby
match "*path", to: "errors#not_found", via: :all,
  constraints: ->(req) { !req.path.start_with?("/reactive/") }
```

At boot the gem warns (`[phlex-reactive] POST /reactive/actions does not resolve
to phlex/reactive/actions …`) when the route is shadowed.

**The `reactive` controller isn't registered (`lazyLoadControllersFrom` apps).**
`lazyLoadControllersFrom("controllers", application)` only registers controllers
under `app/javascript/controllers/`. The gem's controller lives outside that dir,
so `data-controller="reactive"` does nothing until you register it explicitly:

```js
// app/javascript/controllers/index.js (or your Stimulus entrypoint)
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

If reactive elements are on the page but the controller never connected, the
runtime logs a console warning (`[phlex-reactive] found N element(s) with
data-controller="reactive" but the reactive controller never connected …`).

---

## The mental model in one picture

```
   ┌── click / input ──────────────────────────────────────────┐
   │                                                            ▼
[ button(**on(:increment)) ]          POST /reactive/actions { token, act, params }
   ▲                                                            │
   │                                          verify signed token (no state trusted)
   │                                          rebuild component (record from DB)
   │                                          run the whitelisted action
   │                                          re-render → <turbo-stream replace id>   (default; an action
   │                                          may return reply.<verb> — see "Controlling the action's reply")
   └──────── Turbo applies it in ◀──────────────────────────────┘

   ...and for OTHER tabs/users:
   model change → Component.broadcast_replace_to(stream) → pgbus SSE → same morph
```

Client actions and server broadcasts **converge on one re-render unit**: the
component, targeted by its `id`.

---

## Quickstart: a live, cross-tab counter

```ruby
# app/components/counter.rb  — see the top of this README for the full class
render Counter.new(count: 0)
```

Open the page in two tabs, click `+` — done. To make it update across tabs when
the underlying record changes, use a record-backed component (below).

---

## Two kinds of reactive component

### 1. Record-backed (the common case)

State lives in an ActiveRecord row. The signed identity is the record's
GlobalID; the server re-finds it on each action. **Always prefer this.**

```ruby
class Todos::Item < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_record :todo             # identity AND the default #id: dom_id(@todo)
  action :toggle
  action :rename, params: { title: :string }

  def initialize(todo:) = @todo = todo

  def toggle
    authorize! @todo, :update?      # YOU authorize — the token only proves identity
    @todo.toggle!(:done)
  end

  def rename(title:)
    authorize! @todo, :update?
    @todo.update!(title:)
  end

  def view_template
    li(**reactive_root(class: ("done" if @todo.done?))) do
      button(**on(:toggle)) { @todo.done? ? "✓" : "○" }
      span { @todo.title }
    end
  end
end
```

> **One include, default `#id` (issue #81).** `include Phlex::Reactive::Component`
> pulls in `Streamable` automatically (the explicit two-include form still works
> and is a harmless no-op). A record-backed component also gets `#id` for free —
> `dom_id(record)`, exactly the id nearly every one wrote by hand — so `def id`
> is only needed to override it, and an explicit `def id` always wins.
> **Caveat:** two *different* component classes rendering the *same* record on
> one page both default to the same `dom_id` and collide — give one an explicit
> prefixed id: `def id = dom_id(@todo, "rich")`. State-backed components still
> must define `#id` (they're frequently multi-instance, so a class-name default
> would silently collide; the loud `NotImplementedError` stays).

### 2. State-backed (signed instance vars)

Sign small, JSON-serializable instance vars into the token. Use it **alone** for
a record-less widget (a counter, a wizard step), or **alongside `reactive_record`**
to carry transient UI state — which field, what mode — next to the row. Both the
record's GlobalID and the state are signed into one token and rebuilt on each
action. Keep state small and JSON-serializable.

```ruby
reactive_state :count, :step       # signed; rebuilt on each action
```

The [inline edit example](https://phlex-reactive.zoolutions.llc/docs/example-inline-edit) combines both: a
`reactive_record :record` plus `reactive_state :attribute, :editing`.

---

## Concrete examples

| Example | What it shows |
|---|---|
| [Counter](https://phlex-reactive.zoolutions.llc/docs/example-counter) | State-backed, the smallest reactive component |
| [Payment split](https://phlex-reactive.zoolutions.llc/docs/example-payment-split) | Live sum-to-total rebalancer — nested bracketed params, a disabled computed field, auto-collected siblings (#64–#67) |
| [Cross-tab chat](https://phlex-reactive.zoolutions.llc/docs/example-chat) | Record-backed action **+ pgbus broadcast** → live sync across tabs/browsers |
| [Live todo list](https://phlex-reactive.zoolutions.llc/docs/example-todo-list) | Per-row components, add/toggle/rename/delete, Enter-to-add, broadcast on change |
| [Inline edit](https://phlex-reactive.zoolutions.llc/docs/example-inline-edit) | Show ↔ edit mode toggle, replacing a Stimulus controller + 3 routes |
| [Notifications / badges](https://phlex-reactive.zoolutions.llc/docs/example-notifications) | Pure broadcast (no client action) — a job pushes a re-render |

The cross-tab chat in ~60 lines of Ruby (and zero JS) is the showcase — see
[docs/examples/chat.md](https://phlex-reactive.zoolutions.llc/docs/example-chat).

---

## API reference

### `Phlex::Reactive::Streamable`

| Method | Use |
|---|---|
| `#id` | Stable DOM id == Turbo Stream target. Must match the root element's `id`. Record-backed components default to `dom_id(record)` (issue #81); everything else implements it (`def id`). An explicit `def id` always wins. |
| `.replace(model = nil, morph: false, **opts)` | `<turbo-stream action=replace target=id>` of a freshly built component; `morph: true` adds `method="morph"` |
| `.update` / `.append(target:)` / `.prepend(target:)` / `.remove` | The other Turbo Stream actions |
| `.broadcast_replace_to(*streamables, model:, morph: false)` | Broadcast a replace over the stream transport (pgbus SSE / Action Cable); `morph: true` morphs in place |
| `.broadcast_append_to(*streamables, target:, model:)` / `_update_` / `_prepend_` / `_remove_` | The broadcast variants |
| `#to_stream_replace` / `#to_stream_morph` / `#to_stream_update` / `#to_stream_remove` | Stream the *already-built* instance (used internally after an action / by `reply`); `#to_stream_morph` morphs in place |

Use in controllers: `render turbo_stream: Counter.replace(counter)`.

### `Phlex::Reactive::Component`

| Macro / helper | Use |
|---|---|
| `reactive_record :name` | Record-backed identity (GlobalID). State = the DB. Also defaults `#id` to `dom_id(record)`. |
| `reactive_state :a, :b` | Signed instance-var identity. Standalone, or combined with `reactive_record` to sign transient UI state alongside the row. |
| `action :name, params: { x: :integer }` | Declare a client-invokable action + its param schema. **Default-deny.** |
| `reactive_root(**overrides)` | Spread onto the root element: emits the component `id` **and** `reactive_attrs` together, so the controller root always carries `#id`. Preferred over `id:` + `reactive_attrs`. `**overrides` (`class:`/`data:`) deep-merge. |
| `reactive_attrs` | Marks an element reactive + carries the signed token (no `id`). Spread alongside `id:` on the **same** element: `div(id:, **reactive_attrs)`. Prefer `reactive_root`, which can't split them. |
| `on(:action, event: "click", **params)` | Spread onto a trigger element. Adds `type=button` for clicks. |
| `on(:action, event: "input", debounce: 300)` | Coalesce rapid events into one round trip after a quiet period (live-as-you-type). |
| `on(:action, event: "keydown.enter")` | Fire only on a specific key — Enter-to-submit / Escape-to-cancel — via Stimulus's native keyboard filter (`event:` passes straight through). See [Keyboard triggers](#keyboard-triggers-enter-to-submit--escape-to-cancel). |
| `on(:action, confirm: "Sure?")` | Gate a destructive trigger behind a confirmation. Defaults to `window.confirm`; override the dialog with [`setConfirmResolver`](#custom-confirmation-dialogs-setconfirmresolver). |
| `on(:search, listnav: "[role=option]")` | Add combobox keyboard navigation — Arrow keys move a client-side highlight, Enter picks (clicks the option's own trigger), Escape clears. See [Combobox keyboard navigation](#combobox-keyboard-navigation-listnav). |
| `on(:close_menu, outside: true)` | Fire only for events **outside** this component's root (close-a-dropdown-on-outside-click). Window-bound; never `preventDefault`s, so links elsewhere keep navigating. |
| `on(:track, event: "scroll", window: true, throttle: 250)` | `window:` binds the trigger to the window (page-level scroll/resize); `throttle:` rate-limits leading-edge — first event fires, the rest drop until the window elapses. Mutually exclusive with `debounce:`. |
| `on(:toggle, optimistic: { checked: :keep })` | Apply a reversible **visual hint** the instant the trigger fires (before the round trip); revert it if the action fails. Cosmetic only. See [Optimistic hints](#optimistic-visual-hints-optimistic). |
| `on(:save, disable_with: "Saving…")` | Disable the trigger + swap its text while the action is pending (a disabled button also swallows a rapid double-click). Shorthand for `loading: { disable: true, text: "Saving…" }`. See [Loading states](#declarative-loading-states-loading--disable_with). |
| `on(:save, loading: { disable: true, class: "opacity-50", text: "…" })` | Full loading form: `disable:`, a loading `class:` (on the trigger or a `to:` target), a `text:` swap. Reverts on settle. |
| `busy_on(:save)` | Mark any element so it carries `data-reactive-busy` **only while `save` is in flight** — a spinner styled with pure CSS, zero Ruby. See [Loading states](#declarative-loading-states-loading--disable_with). |
| `on(:action, once: true)` | Fire at most once, then unbind (Stimulus's native `:once`). |
| `on_client(:click, js.toggle("#menu"))` | **Client-only** trigger: applies declared DOM ops with ZERO round trip — no token, no POST, ever. Takes the same `window:`/`once:`/`outside:` modifiers. See [Client-only ops](#client-only-ops-on_client--js--zero-round-trips). |
| `js` | The immutable op builder behind `on_client`: `show`/`hide`/`toggle` (the `hidden` attribute, with an optional `transition:`), `add_class`/`remove_class`/`toggle_class`, `set_attr`/`remove_attr`/`toggle_attr` (allowlisted names), `focus`/`focus_first`, and `dispatch` — chainable. |
| `reactive_input(:param, **attrs)` / `reactive_select(:param, **attrs)` | Render a control already bound to an action param (no magic `name:`). |
| `reactive_field(:param, **attrs)` | The attribute hash behind the above — spread onto any control. |
| `nested_update!(:assoc, attrs)` | Map a nested param onto `<assoc>_attributes` with id preservation; update the record. |
| `reactive_collection :name, item:, container:, count:, empty:, size:` | Declare an add/remove-row list once; actions call `reply.append`/`prepend`/`remove`. See [Reactive collections](#reactive-collections-addremove-rows--count--empty-state). |
| `reply.replace` / `.morph` / `.update` / `.remove` / `.redirect(url)` / `.with(*)` / `.js(ops)` | Return from an action to control the reply (flash, remove, redirect, multi-stream, server-pushed client ops). See [Controlling the action's reply](#reply--controlling-the-actions-reply). |
| `reply.append(name, model)` / `.prepend(...)` / `.remove(name, model)` | Add/remove a row in a declared `reactive_collection` (row + count + empty-state in one reply). |

Param types: `:string` (default), `:integer`, `:float`, `:boolean`, `:file`.
Anything not in the schema is dropped before reaching your method.

**File uploads (`:file`).** Declare `:file` (or `[:file]` for multiple) to accept
an uploaded file in a reactive action — attach a document/receipt/image to the
record without dropping out to a bespoke controller. When the reactive root holds
a populated `<input type="file">`, the client sends the action as multipart
`FormData` (instead of JSON) — `token` + `act` as fields, scalar params as fields,
any nested/array params bracket-expanded into `params[key][sub]` /
`params[key][index]` fields (the same Rails-form shape, so a JSON body and a
multipart body coerce identically — #39), and the file(s) appended; the endpoint
coerces `:file` to the `ActionDispatch::Http::UploadedFile`, passed through
untouched. A non-file value sent to a `:file` param is dropped (the keyword
default applies — never a fabricated file). Token threading and the
re-render/morph are identical; only the request encoding changes when a file is
present.

```ruby
reactive_record :document
action :upload, params: { file: :file, caption: :string } # single (has_one_attached)
action :upload_pages, params: { pages: [:file] }           # multiple (has_many_attached)

def upload(file: nil, caption: nil)
  @document.file.attach(file) if file
  @document.update!(title: caption) if caption.present?
end

def view_template
  form(**on(:upload, event: "submit")) do
    input(type: "file", name: "file")
    input(name: "caption")
    button(type: "submit") { "Upload" }
  end
end
```

> **One multipart caveat:** `FormData` can't carry an *empty* array or hash, so on
> the multipart (file-present) path an empty `[]`/`{}` param is **omitted** and the
> action's keyword default applies — it does **not** arrive as an explicit empty
> collection the way it does over JSON. If you rely on sending `tags: []` to clear
> a collection, send that action *without* a file (the JSON path). A non-empty
> nested/array param rides along fine next to a file.

**Array & nested params.** Wrap a type in an array for an array param, or a hash
schema in an array for Rails-style nested attributes — so one reactive action can
mirror a normal nested-attributes update instead of forcing a per-row component:

```ruby
action :save, params: {
  date: :string,
  bank_account_ids: [:integer],                         # array of scalar
  invoice_items_attributes: [                            # array of hash
    { id: :integer, quantity: :float, price: :float, _destroy: :boolean }
  ]
}

def save(date:, bank_account_ids:, invoice_items_attributes:)
  @invoice.update!(date:, bank_account_ids:, invoice_items_attributes:)
end
```

Nested coercion recurses per field, drops undeclared nested keys, and accepts an
array as either a JSON array or a Rails index hash (`{ "0" => …, "1" => … }`).

**Model-scoped form fields just work.** A standard Rails `Form(model: @invoice)`
names its inputs `invoice[date]`, `invoice[status]`, … and the client posts those
names verbatim. A nested schema matches them with zero field renaming — the
endpoint expands bracket notation before coercion, so `invoice[date]` nests under
`invoice` and `invoice_items_attributes[0][qty]` becomes the index-hash form
above:

```ruby
action :save, params: {invoice: {date: :string, status: :string}}
# client posts { "invoice[date]": "…", "invoice[status]": "…" }  → save(invoice: { date:, status: })
```

> **A flat schema silently drops bracketed names (issue #67).** The schema must
> mirror the field *names*, not the conceptual params. Because the endpoint
> expands `invoice[date]` to `{ "invoice" => { "date" => … } }` **before**
> matching the schema, a flat `params: { date: :string }` matches nothing — the
> top-level key is now `invoice`, not `date`. There is no error: the action just
> receives its keyword defaults (`date` never set). If your inputs are named
> `invoice[…]` (any `Form(model:)`-style form), nest the schema under `invoice:`
> to match. When in doubt, read a field's real `name` attribute and shape the
> schema to it.

**Nested reactive components compose.** A reactive component rendered inside
another is its own root — field collection stops at nested
`data-controller="reactive"` roots, so an outer action collects only *its own*
named inputs, never a nested component's. An invoice editor's `save` sees its
flat fields; each line-item row's `quantity`/`price` belong to that row's own
action. No name-disjointness workarounds required.

**Debounced triggers (live-as-you-type).** Pass `debounce:` (milliseconds) to
coalesce rapid events — typically keystrokes on an `"input"` trigger — into a
single action round trip fired after the quiet period, instead of one POST per
keystroke. A blur flushes a pending dispatch so the last edit is never dropped.
Omit `debounce:` for the immediate-dispatch default.

```ruby
# Recompute a total live as the user types, without hammering the endpoint.
input(**mix(on(:update, event: "input", debounce: 300), name: "quantity", value: @item.quantity))
```

**Event modifiers — `outside:`, `window:`, `once:`, `throttle:`.** Four more
`on(...)` options cover the page-level trigger patterns that otherwise need a
hand-written Stimulus controller:

- `outside: true` fires the action only for events whose target is **outside**
  this component's root — the close-a-dropdown-on-outside-click pattern. An
  event inside the root is a complete client-side no-op. Implies `window:`.
- `window: true` binds the trigger to the window (Stimulus's native `@window`)
  for page-level events like `scroll`/`resize`. Window-bound triggers are
  **never `preventDefault`-ed** — a mounted dropdown must not kill link clicks
  elsewhere on the page — and skip the forced `type="button"`.
- `once: true` fires at most once, then unbinds (Stimulus's `:once`).
- `throttle: 250` rate-limits **leading-edge**: the first event fires
  immediately, further events are dropped until the window elapses. The mirror
  of `debounce:` (trailing-edge) — passing both raises `ArgumentError`.

```ruby
# A dropdown that closes itself on any click outside — no Stimulus controller.
div(**mix(reactive_root, on(:close_menu, outside: true))) do
  button(**on(:toggle_menu)) { "Menu" }
  ul { menu_items } if @open
end

# Throttled page-scroll tracking.
div(**mix(reactive_root, on(:track, event: "scroll", window: true, throttle: 500)))
```

These four (like `debounce:`/`confirm:`/`listnav:`) are **reserved keyword
names** on `on(...)` — no longer usable as free action params.

### Optimistic visual hints (`optimistic:`)

Every reactive action waits a full round trip for its visual change — and it's
worse than neutral for a checkbox: the client `preventDefault`s the trigger, so
an `on(:toggle)` checkbox never even **flips** until the morph arrives.
`optimistic:` gives Livewire's "flip it client-side, let the morph correct" (and
React's `useOptimistic`): a small, **always-reversible**, cosmetic vocabulary
applied the instant the trigger fires and **reverted** if the round trip fails.

Hints are visual **only** — never data, never a computed value (that would be
client state the DOM can't be trusted to hold). Supported ops in the hint hash:

- `toggle_class:` / `add_class:` / `remove_class:` — a class string or array,
  applied to the **trigger** by default, or to a `to:` selector scoped to the
  root (`to: :root` targets the root element itself).
- `checked: :keep` — for a **click-bound** checkbox/radio, the client skips its
  unconditional `preventDefault` so the **native flip happens now** (a bare
  toggle click has no navigation default to lose). `on(...)` also skips the
  forced `type="button"` it normally adds to click triggers — that would destroy
  the very checkbox being toggled — so you supply the real `type="checkbox"` /
  `type="radio"`. On a `change`-bound control the flip is already native
  (`change` isn't cancelable) — `:keep` then only contributes the failure revert.
- `hide: true` — hides the target immediately.

```ruby
# A checkbox that flips instantly; the label paints in the same gesture. The
# morph reconciles from server truth; a failure snaps both back.
input(type: "checkbox", checked: @todo.done,
  **mix(on(:toggle, event: "change", optimistic: { checked: :keep, toggle_class: "is-done", to: ".status" }),
    name: "done"))

# Instant delete: hide the row NOW, remove it on the reply.
button(**on(:destroy, confirm: "Delete?", optimistic: { hide: true, to: :root })) { "Delete" }
```

**The success/failure contract (load-bearing):**

- **On failure** — any branch (`redirected` / `http` / `content-type` /
  `network`, plus a client-side `apply` throw) — the client replays the exact
  **inverse** ops, guarded by `isConnected` (a detached row is skipped, it's
  gone anyway). The hint stored on the queued request, so the serialized
  per-controller queue reverts the **right** request's hint.
- **On success there is NO cleanup.** A reply that re-renders the root
  **overwrites** the hint with server truth. A reply that does **not** re-render
  the root (`reply.remove`, streams-only) **leaves the hint standing** — that's
  the `hide: true` + `reply.remove` instant-delete recipe working as intended:
  the row hides, then removes, and never flashes back.

`optimistic:` (like `debounce:`/`confirm:`/`throttle:`) is a **reserved keyword
name** on `on(...)`. An unknown hint op, a `checked:` value other than `:keep`,
or a non-hash raises at render — a dead hint fails loudly, never silently.

### Declarative loading states (`loading:` / `disable_with:`)

Between the click and the morph, the user needs to see that something is
happening — and a mutating button needs to stop a rapid double-click from firing
twice. `loading:` / `disable_with:` are Livewire's `wire:loading` +
`phx-disable-with` and LiveView's `phx-click-loading`, without a Stimulus
controller. Both are **reserved keyword names** on `on(...)`.

The moment a request is **enqueued** — covering the queue wait, not just the
fetch — the trigger and root get the always-on busy vocabulary, and (if declared)
the loading hint applies; everything reverts when the round trip settles
(success **or** failure), guarded so a re-rendered trigger is never clobbered.

**`disable_with:` — the common case.** Disable the trigger and swap its text
while pending. A disabled button fires no further clicks, so a rapid double-click
enqueues exactly **one** POST (the queue only serializes tokens — it does not
dedupe; the disable is what dedupes):

```ruby
button(**on(:save, disable_with: "Saving…")) { "Save" }
```

**`loading:` — the full form.** A hash of:

- `disable: true` — disable the trigger while pending.
- `class: "…"` / `[ … ]` — a loading class on the **trigger**, or on a `to:`
  selector scoped to the root (`to: :root` targets the root element itself).
- `text: "Saving…"` — swap the trigger's `textContent` while pending.

```ruby
button(**on(:destroy, confirm: "Sure?", loading: { disable: true, class: "opacity-50 pointer-events-none" })) { "Delete" }
```

`disable_with: "Saving…"` is the shorthand for `{ disable: true, text: "Saving…" }`
and, if you pass both, merges over an explicit `loading:` (its `text`/`disable`
win). An unknown loading key or a non-hash `loading:` raises at render.

**The `aria-busy` + `data-reactive-busy` contract (always on — zero Ruby).**
Independent of any `loading:` hint, **every** reactive round trip marks the DOM
for the whole enqueue→settle window, so you can style spinners and dimming with
pure CSS:

- the **trigger** and the **root** carry `data-reactive-busy="<action>"` (a
  **space-separated set** on the root, so two concurrent actions never clobber);
- the **root** carries `aria-busy="true"` (driven by a pending counter — it
  clears only when the last in-flight request settles, so overlapping actions
  don't clear it early);
- `busy_on(:action)` marks any element inside the root so **it** gets
  `data-reactive-busy` toggled **only while that action is in flight** — a scoped
  spinner:

```ruby
button(**on(:save, disable_with: "Saving…")) { "Save" }
span(**busy_on(:save), class: "spinner")
```

phlex-reactive ships **no CSS** for these — you own the styling. A minimal
example (not shipped — copy into your app's stylesheet):

```css
/* Reveal a busy_on / aria-busy spinner only while its action is in flight. */
.spinner { display: none; }
[data-reactive-busy] .spinner,
[data-reactive-busy].spinner { display: inline-block; }

/* Dim the whole component during any round trip. */
[aria-busy="true"] { opacity: 0.6; transition: opacity 120ms ease; }
```

The disable + text swap apply **only at enqueue**, never during a `debounce:`
quiet period — so a debounced `input` trigger (whose element *is* the text field)
is not disabled mid-typing. On settle the text is restored only if it still
matches what was swapped in; a morph that rendered a **new** server label is left
alone.

### Client-only ops (`on_client` + `js`) — zero round trips

Not every interaction needs the server. A tab switch, a dropdown, an accordion
— purely visual state — used to mean either a wasteful signed round trip or the
very Stimulus controller this gem exists to eliminate. `on_client` binds a DOM
event to a chain of **declared DOM operations** that the one generic controller
applies locally: **no token, no params, no POST, ever.**

```ruby
def view_template
  div(**mix(reactive_root, on_client(:click, js.hide("#menu"), outside: true))) do
    # Tabs: one op chain per tab — hide all panels, show one, restyle the tabs.
    button(**on_client(:click, js.hide(".panel").show("#panel-2")
      .remove_class(".tab", "active").add_class("#tab-2", "active"))) { "Tab 2" }

    # A menu that opens client-side and closes on ANY outside click (the root
    # carries the window-bound trigger above).
    button(**on_client(:click, js.show("#menu"))) { "Menu" }
    div(id: "menu", hidden: true) { menu_items }
  end
end
```

The `js` builder is immutable (each verb returns a new chain) and its
vocabulary is a fixed whitelist mirrored by the client: `show`/`hide`/`toggle`
flip the `hidden` attribute; `add_class`/`remove_class`/`toggle_class` take one
or more classes. Targets are CSS selectors resolved **within the component's
root** (nested reactive components are never touched — same ownership rule as
field collection); `:root` targets the root element itself; `global: true` on
an op escapes to the whole document. An op name the client doesn't recognize
logs a warning and is skipped — the rest of the chain still applies.

**Attributes, focus, dispatch, and transitions.** Beyond visibility and classes,
the same chain covers the rest of the client-only vocabulary:

```ruby
button(**on_client(:click, js
  .toggle("#menu", transition: %w[transition-opacity opacity-0 opacity-100])
  .toggle_attr(:root, "aria-expanded")   # accessible disclosure state
  .focus_first("#menu")                   # move focus into the opened menu
  .dispatch("app:menu-toggled", detail: { open: true }))) { "Menu" }
```

- **`set_attr(to, name, value)` / `remove_attr(to, name)` / `toggle_attr(to, name)`**
  mutate an attribute. The **attribute name is allowlisted, enforced twice** — at
  build time in Ruby (an offending name raises) and again in the client
  interpreter (a hand-built op is warned and skipped). Refused: **event handlers**
  (`on*` → XSS), **URL-bearing** names (`href`, `src`, `srcdoc`, `action`,
  `formaction`, `xlink:href` → a `javascript:` navigation surface), and **`style`**
  (CSS injection — use classes). The **intended surface** is class ops plus
  `hidden`, `disabled`, `open`, `selected`, and any `aria-*` / `data-*` attribute.
- **`focus(to)`** focuses the first match; **`focus_first(to)`** focuses the first
  focusable descendant of the match (e.g. the first menuitem inside an opened
  menu).
- **`dispatch(name, to: nil, detail: {})`** emits a **bubbling `CustomEvent`** so
  another component or a plain Stimulus controller can react to a client-only
  interaction — `to:` picks the element (default: the component root), `detail:`
  is the payload.
- **`transition: [during, from, to]`** on `show`/`hide`/`toggle` animates the
  visibility flip: `during`+`from` are applied, then `from`→`to` swaps on the next
  frame, and the helper classes are cleaned up on `animationend` (with a timeout
  fallback, so an element with no animation never leaves them stuck). The op chain
  is never blocked — later ops (a `focus`, a `dispatch`) run immediately.

`window:`, `once:`, and `outside:` compose exactly like `on(...)`'s event
modifiers: the dropdown above closes on any click outside the component, and
window-bound triggers never `preventDefault`, so links elsewhere keep working.

**Client ops are ephemeral UI — the one contract to internalize.** Any server
re-render of the component (an action reply, a broadcast, a morph) rebuilds
from server state and resets whatever the ops toggled: the menu closes, the tab
snaps back. That is by design — the same caveat LiveView's JS commands carry.
For state that must survive a re-render (an edit mode, a selection the server
should know about), use a signed `action` instead; `on_client` is for state the
server should never care about.

**Auto-collected sibling fields — the read contract.** A reactive action doesn't
just receive its own trigger's value: the client gathers **every named control**
in the reactive root (`input[name]`, `select[name]`, `textarea[name]`, and named
rich-text/`contenteditable` editors) and merges them under the action's params,
so one action reads the whole form. Explicit `on(:act, x: …)` params win over a
collected field of the same name; collection stops at nested reactive roots (see
*Nested reactive components compose* above). Two things worth pinning down:

- **Timing — params reflect the DOM at dispatch, not a pre-event snapshot
  (issue #65).** Field values are read when the request is sent (after the
  debounce quiet period, if any), so a `change`/`input` trigger sees **its own
  field's new value and every peer's current value.** There is no capture of the
  values as they were *before* the interaction — if your computation needs a
  peer's prior value (e.g. a spill-back that folds an overflow into the edited
  field), that peer's current DOM value *is* the prior value only because nothing
  else has changed it yet. Read at dispatch time, trust the current DOM.
- **Disabled fields ARE collected (issue #66) — deliberately different from a
  native form.** A `<form>` submit omits `disabled` controls; reactive collection
  does **not** check `disabled`, so a disabled field that carries a
  computed/display value (a read-only `total` the client keeps in sync) reaches
  the action. This is intentional — it's what makes "read a computed disabled
  field" work. If you need form-submit parity (drop the disabled value), give the
  control no `name`, or make it `readonly` instead of `disabled` when you *do*
  want it collected by both paths.

**Keyboard triggers (Enter-to-submit / Escape-to-cancel).** `event:` is
interpolated straight into the Stimulus action descriptor, so any Stimulus event
string works — including its **native keyboard filters**. Pass `event:
"keydown.enter"` to fire only on Enter, `event: "keydown.esc"` for Escape — the
classic "Enter adds the row", "Escape cancels the edit" interactions. The action
runs *only* on that key, not on every keypress — no client JavaScript, no
`event.key` check of your own, and no new option to learn (it's Stimulus's own
[keyboard-filter syntax](https://stimulus.hotwired.dev/reference/actions#keyboardevent-filter)):

```ruby
# Enter in the composer adds the todo (same action as the Add button).
input(**mix(on(:add, event: "keydown.enter"), name: "title", placeholder: "New todo…"))

# Inline editor: Enter on the field saves; a separate control cancels on Escape.
input(**mix(on(:save, event: "keydown.enter"), name: "title", value: @todo.title))
button(**on(:cancel, event: "keydown.esc")) { "Cancel" }
```

The filter tokens are Stimulus's (`enter`, `esc`, `space`, `up`, `down`, a bare
letter, …). Because a keyboard trigger isn't a click, it does **not** get the
`type="button"` a click trigger does. Folding the key into `event:` keeps `key`
free as an ordinary action-param name (`on(:switch, key: "pgbus")` still passes
`key` through as a param).

> **One action per element.** Each trigger element carries a single reactive
> action (its `data-reactive-action-param`), so you can't put `on(:save, event:
> "keydown.enter")` *and* `on(:cancel, event: "keydown.esc")` on the **same**
> input — the second would overwrite the first's action name. Bind each key
> trigger to its own element (the field saves on Enter; a Cancel button — or the
> field's own blur — handles Escape), as above.

### Combobox keyboard navigation (`listnav:`)

A searchable list needs Arrow keys to move a highlight, Enter to pick, Escape to
close — interactions that are *ephemeral client UI state* (a highlight per
keystroke would be absurd as a server round trip). Pass `listnav:` (a CSS
selector for the option elements) to a search trigger and the generic controller
handles all of it client-side, with no bespoke Stimulus controller:

```ruby
# The search input: debounced live search + keyboard list navigation.
input(**mix(
  on(:search, event: "input", debounce: 200, listnav: "[role=option]"),
  name: "query", value: @query
))

# Each option is BOTH a listnav target (role=option) and its own reactive
# select trigger — Enter just clicks the highlighted one.
button(**mix(on(:select, name: opt), role: "option")) { opt }
```

`listnav:` appends Stimulus's native keyboard filters
(`keydown.down/up/enter/esc`) to the input's `data-action`. Arrow Up/Down move a
`data-reactive-highlighted` marker among the options **with no round trip**;
Enter **clicks the highlighted option** — so selection runs through its normal
`on(:select)` reactive action (signed, default-deny, authorized like any other);
Escape clears the highlight. Only the highlight is client-side — the selection
stays a real signed action, and the highlight is never shipped as trusted state.

**Combining `on(...)` / `reactive_attrs` with your own attributes.** Both return
a hash that includes a `data:` key. Spreading them *and* passing another `data:`
(or `class:`, `id:`) would clobber it — use Phlex's `mix` to deep-merge. For the
**root**, prefer `reactive_root`, which already `mix`es id + token for you:

```ruby
# ✅ merges cleanly (data-action survives, your data-testid/class are added)
button(**mix(on(:increment), class: "btn", data: { testid: "inc" })) { "+" }
div(**reactive_root(class: "card", data: { testid: "root" })) { ... }   # id + token + your attrs

# ❌ the extra data: overwrites on()'s data:, so the action never binds
button(**on(:increment), data: { testid: "inc" }) { "+" }
```

> **The reactive root must carry `#id` (issue #48).** The server targets your
> component's `#id` and the client self-matches its next signed token by the root
> element's `id`. `reactive_attrs` does **not** emit the id — so if you put `id:`
> on a **child** instead of the `**reactive_attrs` element, the root's id is empty,
> token threading falls back to the first token in the response, and the *next*
> action silently fails with **HTTP 403**. Use `div(**reactive_root)` (it emits id
> + token on one element) so the id can't land on the wrong node; if you spread
> `reactive_attrs` directly, keep `id:` on the **same** element
> (`div(id:, **reactive_attrs)`). The controller `console.warn`s on connect when a
> reactive root has no id.

**Binding inputs to action params (drop the magic `name:`).** A field's value
travels with an action only if its `name` equals the param. Hand-writing
`name: "value"` on every input is easy to forget — the action then silently gets
nothing. `reactive_input`/`reactive_select` emit the binding for you (the trigger
stays on the button, so focusing the field doesn't dispatch and collapse edit
mode):

```ruby
action :save, params: { value: :string, status: :string }

def view_template
  span(**reactive_root) do
    reactive_input(:value, value: @record.name)            # <input name="value" …>
    reactive_select(:status) do                            # <select name="status">…</select>
      %w[open closed].each { |s| option(value: s, selected: s == @record.status) { s } }
    end
    button(**mix(on(:save), data: { testid: "save" })) { "Save" }
  end
end
```

`reactive_field(:value, **attrs)` returns just the attribute hash if you'd rather
spread it onto a control yourself. An explicit `name:` still wins (escape hatch).

**Editing an associated record (`accepts_nested_attributes_for`).** `nested_update!`
maps a declared nested param straight onto `<assoc>_attributes` and carries the
existing record's id, so `update_only:` matches it in place instead of building a
second `has_one` (the boilerplate that's easy to get subtly wrong):

```ruby
# Account has_one :address; accepts_nested_attributes_for :address, update_only: true
action :save, params: { address: { street: :string, city: :string } }

def save(address:)
  nested_update!(:address, address)   # update!(address_attributes: address.merge(id: @account.address&.id))
end
```

`nested_attributes(:address, address)` returns the id-merged hash without
updating, if you need to combine it with other attributes.

### Custom confirmation dialogs (`setConfirmResolver`)

`on(:action, confirm: "Really delete this?")` gates a destructive trigger behind
a confirmation. Because the reactive controller preempts the event (its own
`preventDefault` + POST), Hotwire's `data-turbo-confirm` — which routes through
`Turbo.config.forms.confirm` — never runs for a reactive trigger. So by default
the gate uses the browser-native `window.confirm` (synchronous, no dependency,
screen-reader friendly).

If your app already themes confirmations (the common Hotwire setup —
`Turbo.config.forms.confirm = (message) => Promise<boolean>`, backed by a styled
modal), reuse that exact dialog for reactive triggers with one line at boot:

```js
import { setConfirmResolver } from "phlex/reactive/confirm"

// Reuse the same themed dialog the rest of the app already uses.
setConfirmResolver((message) => window.Turbo.config.forms.confirm(message))
```

The resolver receives the `confirm:` message and returns `true`/`false` (or a
`Promise` of one). It may be **async** — the controller `await`s it, then runs
the action only on a truthy result; a falsy result (or a rejected promise — e.g.
the user dismissed the dialog) cancels the action, exactly like declining the
native prompt. The native default is always prevented up front, so a `submit`
trigger never navigates while the dialog is open.

Unset, behavior is identical to the native `window.confirm` — the `confirm:`
markup and `on(...)` API are unchanged; only the client's resolution strategy
gains a seam.

### `reply` — controlling the action's reply

By default an action re-renders its component in place. To do more, **return**
`reply.<verb>` — a subject-bound builder available in every component. It governs
only the actor's HTTP reply (cross-tab updates still use
`broadcast_*_to(..., exclude: reactive_connection_id)`). Returning anything else
keeps the default, so existing actions are unaffected.

`reply` reads cleanly: the component is the implicit subject (no `self` to
thread) and there's no constant to qualify (it's a method, so a namespaced
component needs no alias):

```ruby
def rename(title:)
  return reply.replace.flash(:error, @todo.errors.full_messages.to_sentence) unless @todo.update(title:)
  reply.replace
end

def approve   = (@row.approve!; reply.remove)          # drop the element
def publish   = (@article.publish!; reply.redirect(article_url(@article)))  # slug changed → Turbo.visit
def add(item:) = reply.replace.stream(Totals.update(@order))               # multi-stream

# Per-field reactive editing (a "spreadsheet" grid): a debounced save fires
# while the user is still typing/tabbing. Morph in place so the focused <input>
# and its in-progress value survive the re-render (issue #28). Note the action is
# named `update`, yet `reply.morph` is unambiguous — the verb is on `reply`:
def update(name:) = (@row.update!(name:); reply.morph)

# Re-render a COMPANION element (a heading mirroring the edited name) alongside self:
def rename(value:) = (@account.update!(name: value); reply.replace.also_update("page_heading", html: @account.name))

# Update ONLY part of the component (issue #30): re-stream just the total cell,
# NOT the whole row. reply.streams emits exactly your streams plus a tiny
# token-only refresh — no full-self replace — so a sibling <input> the user is
# mid-typing in is never torn down. The signed token still rolls forward.
def update(quantity:, price:) = (@item.update!(quantity:, price:); reply.streams(Totals.update(@item)))
```

| Builder | Reply |
|---|---|
| `reply.replace` / `reply.update` | re-render in place (default; `replace` is an outerHTML swap, `update` morphs inner HTML) |
| `reply.morph` / `reply.replace(morph: true)` | re-render in place via Idiomorph (`method="morph"`) — preserves the focused `<input>` + caret; for per-field reactive editing (issue #28) |
| `.also_update(target, html:)` | also re-render a companion element by DOM id; `html` is a plain string (escaped) or a Phlex component |
| `.also_replace(component, morph: false)` | also re-render another Streamable component, targeting its own `#id`; `morph: true` morphs it in place |
| `.flash(level, content, target: …)` | append a flash; `content` is a plain string (escaped, wrapped in a level-carrying `<div>` — see [Flash levels](#flash-levels)) or a Phlex component (rendered verbatim; off-request — no Rails `flash`); target defaults to `Phlex::Reactive.flash_target` (`"flash"`) |
| `reply.remove` | remove the element (backed by `Streamable#to_stream_remove`) |
| `reply.redirect(url)` | client-side `Turbo.visit` (pass a `*_url`); rides a `reactive:visit` turbo-stream, not an HTTP 3xx |
| `reply.streams(*streams)` | **partial update** — emit exactly these streams (no full-self replace) + a tiny token-only refresh, so live inputs survive; for per-field grid editing (issue #30) |
| `.js(ops, target: …)` | also push **client DOM ops** (focus, dispatch, class/attr toggles) over a `reactive:js` stream, applied AFTER the render — `reply.morph.js(js.focus("[name=next]"))` focuses the morphed field (issue #97) |
| `reply.with(*streams)` / `#stream(*more)` | multi-stream (self re-render still injected for the token) |

`.flash`/`.stream`/`.also_*` are additive on a self-replace, so the component's
signed token always refreshes. **`reply.streams`** is the exception that proves
the rule: it deliberately skips the full-self replace (so your hand-built streams
update only the targets you name) and refreshes the token via a tiny inert
`reactive:token` stream instead — the token rolls forward without re-rendering
(and clobbering) the component's live inputs.

#### Flash levels

The level reaches the wire (issue #77). **String** content is wrapped in a
level-carrying `<div>`, so `:error` and `:notice` are styleable:

```html
<div class="reactive-flash reactive-flash--error" data-reactive-flash-level="error">
  Save failed
</div>
```

Style against `.reactive-flash--{level}` (the class) and hook scripts/tests on
`data-reactive-flash-level` (the data attribute). The string keeps the same
injection contract as before, applied inside the wrapper: a plain string is
HTML-escaped (a model value can't inject markup); an `html_safe` string passes
verbatim.

Prefer your own markup? Two escape hatches:

```ruby
# 1. Pass a Phlex component as the content — rendered VERBATIM, no wrapper
#    (you own the markup entirely, including the level styling):
reply.replace.flash(:error, Alert.new(level: :error, message: msg))

# 2. Or configure a flash component ONCE — string flashes render through it
#    (instantiated new(level:, content:)); component content still bypasses it:
Phlex::Reactive.flash_component = MyFlash   # default nil → the built-in wrapper
```

#### Server-pushed client ops (`reply.js` + `broadcast_js_to`, issue #97)

Sometimes the server needs the client to do something other than swap HTML —
focus the next field after a save, dispatch an app event to a toast host, add an
unread badge — WITHOUT re-rendering to make it happen. `reply.<verb>.js(ops)`
chains a `reactive:js` stream carrying declared client DOM ops (the same `js`
builder as [`on_client`](#client-only-ops-on_client--js--zero-round-trips))
onto any reply. The op stream rides **after** the render streams, so a focus op
sees the freshly rendered/morphed DOM:

```ruby
def save(title:)
  @todo.update!(title:)
  # Morph in place, THEN focus the next field + tell a toast host we saved:
  reply.morph.js(js.focus("[name=next_field]").dispatch("app:saved", detail: { id: @todo.id }))
end
```

`target:` scopes op resolution on the client; it defaults to the bound
component's id for `replace`/`morph`/`update` (so `@root` and component-relative
selectors just work), and to document-scope for a subject-free `reply.with`.

The same ops broadcast to **every** subscriber of a stream over the usual
transport (Action Cable **or** pgbus) — a background nudge to all viewers:

```ruby
# In a model/job: light up the bell in every viewer's tab, minus the actor's own.
Notifications::Badge.broadcast_js_to(user, :alerts,
  js.add_class("#bell", "has-unread"), exclude: reactive_connection_id)
```

`broadcast_js_to` **refuses focus-class ops** (`focus`/`focus_first` raise
`ArgumentError`): broadcasting focus would steal it in every subscriber's tab, so
focus is an actor-reply concern only. Everything else is a fair broadcast (class
and attribute toggles, `dispatch`). As with `on_client`, the ops are
whitelist-interpreted client-side — an unknown op warns and is skipped — and the
ops attribute is HTML-escaped, so a value can't break out of it. `reactive:js`
is not a self-render: it never counts toward the token refresh, so the reply's
signed token still rolls forward exactly as it would without the ops.

> **Ephemeral by design.** Like `on_client`, server-pushed ops are transient UI:
> the next server re-render of the component resets whatever they toggled. State
> that must survive a re-render belongs in a signed `action`, not an op.

#### Record-authorized, transient-state actions (issue #64)

A `reactive_record` component isn't obligated to persist or broadcast — the
record can be there purely for **identity + authorization** while the action's
real job is to recompute **live, unsaved form values** the user is mid-edit. The
record is re-located and instantiated on each action (`from_identity`), never
auto-saved and never auto-broadcast; persistence and cross-tab broadcast are both
opt-in (you call `record.update!` / `broadcast_*_to` yourself). Pair that with
`reply.streams` and you get a first-class "authorize via the row, compute over
the params, stream a partial update, touch neither the DB nor peer tabs" action:

```ruby
class Invoice::PaymentFields < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_record :invoice   # identity + authorization ONLY — not persisted here
  action :rebalance, params: { invoice: { field_a: :integer, field_b: :integer,
                                          field_c: :integer, total: :integer } }

  def rebalance(invoice:)
    authorize! @invoice, :update?          # the token proves identity, not permission
    result = recompute(invoice)            # pure computation over the collected params
    reply.streams(*set_value_streams(result))  # NO persist, NO broadcast
  end
end
```

This is deliberate, not a misuse: `reply.streams` is exactly the reply for "emit
these targeted updates, roll the token forward, and leave everything else — the
DB, the other tabs, the sibling inputs the user is typing in — untouched."
Broadcasting is deliberately omitted so peer tabs with their own in-flight edits
aren't clobbered. Authorize the record as always — identity is never permission.

> **Under the hood.** `reply.<verb>` returns a `Phlex::Reactive::Response` — the
> immutable value object the endpoint reads. You can build one directly
> (`Phlex::Reactive::Response.replace(self)`) and it still works, but `reply` is
> the preferred surface; treat `Response` as an internal detail.
> **`html:`/`content` escaping.** A plain string is **HTML-escaped** by Turbo, so
> `html: @account.name` is safe even for user-supplied values. To emit intentional
> markup, pass a **Phlex component** (`html: Heading.new(name: @record.name)`) —
> rendered and auto-escaped through the renderer — or an `html_safe` string for
> raw HTML you control.

### Failure UX & lifecycle events

The generic controller dispatches three bubbling, composed `CustomEvent`s
around every action round trip, so an app can toast an error, instrument
latency, veto a dispatch, or build retry UI **without forking the controller**:

| Event | When | `event.detail` |
|-------|------|----------------|
| `reactive:before-dispatch` | after the trigger's `preventDefault`/`confirm:`, **before** debounce/enqueue | `{ action, params, element }` — cancelable: `event.preventDefault()` skips the round trip entirely (nothing is scheduled) |
| `reactive:applied` | after the response's token was captured and the streams were handed to `Turbo.renderStreamMessage` | `{ action, params, html }` |
| `reactive:error` | in every failure branch of the round trip | `{ action, params, kind, status?, body?, retry }` |

`reactive:error`'s `kind` tells you **what** failed:

| `kind` | Meaning | Extra detail |
|--------|---------|--------------|
| `redirected` | the POST was redirected (an auth `before_action` / CSRF guard bounced it) | `status`, `retry` |
| `http` | non-2xx response (403 default-deny/authorization, 400 bad token, 404 record gone, 500 …) | `status`, `body`, `retry` |
| `content-type` | 200, but not a turbo-stream (an HTML error page, a misconfigured route) | `status`, `retry` |
| `network` | `fetch` itself rejected (offline, DNS, connection reset) — the server never saw the request | `retry` |
| `apply` | the server processed the action successfully, but something AFTER the fetch threw (a malformed response, a Turbo render error) | no `retry` |

`apply` covers a throw in the controller's own post-fetch code — not a
throwing listener on `reactive:applied` itself. Per the DOM spec,
`EventTarget#dispatchEvent` never propagates a listener's exception back to
its caller (it's reported to the console instead), so a listener that throws
can't surface as `reactive:error` at all — it just logs and the round trip is
otherwise unaffected.

`detail.retry()` re-enters the controller's request queue: it re-reads the
**freshest** signed token and re-collects the component's fields at send time,
so nothing stale is replayed. It fires no second `reactive:before-dispatch`
(one veto per user gesture), and it no-ops with a `console.warn` once the
component has left the DOM. The existing `console.error` logging is unchanged —
the events add hooks, they don't replace the log.

**`kind: "apply"` carries no `retry()` at all** — by the time this fires the
server has already completed the mutation, so retrying would re-POST an
action that already succeeded (potentially a non-idempotent one). Only the
four fetch/response-shaped kinds above are retriable.

The events bubble from the component's root element (or from `document` when
the root was detached by the failing round trip), so they compose with plain
Stimulus listening — a global toaster is one attribute on an ancestor:

```html
<body data-controller="toast" data-action="reactive:error->toast#show">
```

```js
// toast_controller.js
show(event) {
  const { kind, status, retry } = event.detail
  this.flash(`Action failed (${kind}${status ? ` ${status}` : ""})`, { onRetry: retry })
}
```

Or veto/instrument at the document level:

```js
document.addEventListener("reactive:before-dispatch", (event) => {
  if (offline) event.preventDefault()           // cancel: nothing is enqueued
})
document.addEventListener("reactive:applied", ({ detail }) => {
  metrics.count(`reactive.${detail.action}.ok`)
})
```

One honest caveat on timing: `reactive:applied` means the turbo-streams were
**handed to Turbo** — `renderStreamMessage` applies them asynchronously, so the
DOM mutation may complete a tick later. If you need post-morph timing, listen
to Turbo's own events (`turbo:before-stream-render` and friends).

### Reactive collections (add/remove rows + count + empty-state)

An add/remove-row list — line items, attachments, tags, comments, a
notifications list — is one of the most common reactive surfaces, and every one
re-implements the same orchestration by hand: append the row to the right
container, remove it on delete, keep a **count badge** in sync, and swap an
**empty-state** in/out as the list crosses 0↔1. `reactive_collection` declares
that contract **once** on the container so each action is a single call.

Declare the collection on the container component, then `reply.append` /
`reply.prepend` / `reply.remove` in the actions:

```ruby
class NotificationsList < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_collection :notifications,
    item: NotificationRow,        # the per-row Streamable component
    container: "notifications",    # the DOM id rows live in
    count: "notifications-count",  # optional companion id (the size badge)
    empty: NotificationsEmpty,     # optional empty-state component
    size: -> { Todo.count }        # resolves the live size (re-counted, never client state)

  action :add, params: {title: :string}
  action :dismiss, params: {id: :integer}

  def add(title:)
    todo = Todo.create!(title:)
    reply.append(:notifications, todo)   # append row + bump count + clear empty-state
  end

  def dismiss(id:)
    Todo.find(id).destroy!
    reply.remove(:notifications, id)     # remove row + bump count + restore empty-state at 0
  end

  # view_template renders the count, the container <ul>, and the empty-state on
  # first paint — the same components the helper streams in/out on each delta.
end
```

| Builder | Reply (one `Response`) |
|---|---|
| `reply.append(name, model)` | append the row into the container + update the count + remove the empty-state when the list crosses 0→1 |
| `reply.prepend(name, model)` | as `append`, but the row goes to the top |
| `reply.remove(name, model)` | remove the row by its `dom_id` + update the count + append the empty-state back when the list crosses →0 |

- **`size:` is the source of truth** — it's *re-counted* server-side after the
  mutation, so the badge and the empty-state are correct-by-construction (no
  off-by-one, no client-held count). `count:`, `empty:`, and `size:` are all
  optional: omit them and only the row stream is emitted.
- **Repeated add/remove just works** — each reply rolls the **container's** signed
  token forward (via the inert `reactive:token` refresh), so the second click from
  the list root is accepted. Without this an add/remove list would be add-once-only
  (correct on the first click, silently rejected after); the helper bakes the
  refresh in so you never hit it.
- **`remove` takes the record or its `dom_id` string** — a just-destroyed
  ActiveRecord still answers `dom_id` correctly, so `reply.remove(:items, todo)`
  works; pass the raw id only if your row `#id` matches `ActiveRecord::RecordIdentifier`.
- **Reply governs the actor's HTTP response only.** For a *cross-tab* live list
  (other viewers see the row appear) keep broadcasting the row with
  `NotificationRow.broadcast_append_to(..., exclude: reactive_connection_id)` —
  `reactive_collection` is the per-actor add/remove + count + empty-state wrapper,
  not a replacement for the broadcast.

### Configuration (`config/initializers/phlex_reactive.rb`)

```ruby
Phlex::Reactive.configure do |c| end if false # (plain accessors below)

# Inherit auth/CSRF/Current from your app on the action endpoint:
Phlex::Reactive.base_controller_name = "ApplicationController"

# Render your authorization library's error as 403:
Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
# or: [ActionPolicy::Unauthorized]

# Use your ApplicationController to render components (app helpers / Current):
Phlex::Reactive.renderer = ApplicationController

# Sign tokens with a dedicated key instead of secret_key_base:
Phlex::Reactive.verifier = ActiveSupport::MessageVerifier.new(ENV["REACTIVE_KEY"])

# Change the endpoint path (default "/reactive/actions"):
Phlex::Reactive.action_path = "/_r/actions"

# Diagnostic error bodies + dropped-param logging (default: Rails.env.local? —
# on in development AND test, off in production):
Phlex::Reactive.verbose_errors = true
```

If you set a custom `action_path`, expose it to the client:

```erb
<meta name="phlex-reactive-action-path" content="<%= Phlex::Reactive.action_path %>">
```

---

## Security

phlex-reactive is built so the easy path is the safe path — but the boundary is
real, so read this once.

- **State is never trusted from the client.** The DOM holds a `MessageVerifier`-
  signed identity — `{component, gid}` (record-backed), `{component, state}`
  (state-backed), or `{component, gid, state}` when a component declares both —
  not raw state. A tampered class, record, or state value fails signature
  verification → 400.
- **Actions are default-deny.** Only methods declared with `action :name` are
  invokable. A public method without `action` is unreachable.
- **You must authorize.** The signature proves the *token is yours*, not that
  *this user may act on this record*. Call your authorizer inside the action
  (`authorize! @todo, :update?`) and register its error in
  `Phlex::Reactive.authorization_errors`.
- **Params are schema-coerced.** Only declared params reach your method, each
  cast to its declared type. No raw mass assignment.
- **CSRF + auth are the host app's.** The endpoint inherits from your configured
  `base_controller_name`. Inherit `ApplicationController` to get CSRF and auth —
  but if you have *public* reactive components, ensure the action path isn't
  force-redirected to a login page for logged-out users.

### Debugging endpoint failures (`verbose_errors`)

Every endpoint failure is warn-logged as `[phlex-reactive] …` in **every**
environment. With `Phlex::Reactive.verbose_errors` on (the default in
development and test via `Rails.env.local?`; off in production), the failure
response ALSO carries a plain-text diagnostic body — the client already prints
it via `console.error` — and param coercion warn-logs every dropped key with
its full bracketed path and reason (`undeclared` / `uncoercible`), including a
hint when a flat name looks like the bracketed twin of a declared nested key
(or vice versa). What each status means:

- **400** — token signature invalid (stale token from before a deploy?
  `secret_key_base` mismatch?), a token class that no longer resolves, or a
  class that resolved but doesn't include `Phlex::Reactive::Component`
- **403** — an undeclared action (the body lists the declared actions) or a
  registered authorization error raised inside the action
- **404** — the signed GlobalID no longer resolves (record deleted)

The flag never changes a status — only the body and the coercion log.

See [docs/security.md](https://phlex-reactive.zoolutions.llc/docs/security) for the threat model and a checklist.

---

## How it beats Stimulus + Turbo (same feature, less code)

A counter, today vs. with phlex-reactive:

<table>
<tr><th>Stimulus + Turbo</th><th>phlex-reactive</th></tr>
<tr><td>

```js
// counter_controller.js
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { url: String }
  increment() { this.#post("increment") }
  decrement() { this.#post("decrement") }
  #post(op) {
    fetch(`${this.urlValue}/${op}`, {
      method: "POST",
      headers: { "X-CSRF-Token": token() },
    })
  }
}
```
```erb
<%# _counter.html.erb %>
<div id="<%= dom_id(@counter) %>"
     data-controller="counter"
     data-counter-url-value="<%= counter_path(@counter) %>">
  <button data-action="counter#decrement">−</button>
  <span><%= @counter.value %></span>
  <button data-action="counter#increment">+</button>
</div>
```
```ruby
# routes + controller
resources :counters do
  member { post :increment; post :decrement }
end
def increment
  @counter.increment!(:value)
  render turbo_stream: turbo_stream.replace(
    dom_id(@counter), partial: "counter",
    locals: { counter: @counter })
end
```

</td><td>

```ruby
class Counter < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_record :counter   # also defaults #id to dom_id(@counter)
  action :increment
  action :decrement

  def initialize(counter:) = @counter = counter

  def increment = @counter.increment!(:value)
  def decrement = @counter.decrement!(:value)

  def view_template
    div(**reactive_root) do
      button(**on(:decrement)) { "−" }
      span { @counter.value }
      button(**on(:increment)) { "+" }
    end
  end
end
```

*One file. No JS. No routes. No partial. No hand-picked target.*

</td></tr>
</table>

---

## Live updates with pgbus (recommended)

[pgbus](https://github.com/mhenrixon/pgbus) replaces Action Cable's transport
with Postgres SSE and fixes its reliability gaps. With it installed,
`broadcast_*_to` and `turbo_stream_from` route over pgbus automatically:

```ruby
class Message < ApplicationRecord
  broadcasts_to ->(m) { [m.room, :messages] }, durable: true
end
```

- **Transactional**: a broadcast inside a transaction that rolls back never
  fires — *and* the DB change is undone. No "ghost" UI updates.
- **Reconnect-safe**: a tab that dropped replays missed messages on reconnect
  (`Last-Event-ID` + PGMQ archive).
- **No race on subscribe**: messages broadcast between render and subscribe are
  replayed, not lost.
- **No Redis, no Action Cable.**

See [docs/broadcasting.md](https://phlex-reactive.zoolutions.llc/docs/broadcasting) and
[docs/transport-pgbus.md](https://phlex-reactive.zoolutions.llc/docs/transport-pgbus).

---

## Documentation

- [Installation & bundler setups](https://phlex-reactive.zoolutions.llc/docs/installation)
- [Mental model & architecture](https://phlex-reactive.zoolutions.llc/docs/architecture)
- [Security & threat model](https://phlex-reactive.zoolutions.llc/docs/security)
- [Broadcasting & live updates](https://phlex-reactive.zoolutions.llc/docs/broadcasting)
- [Transport: pgbus vs Action Cable](https://phlex-reactive.zoolutions.llc/docs/transport-pgbus)
- [Testing reactive components](https://phlex-reactive.zoolutions.llc/docs/testing)
- [Performance & benchmarking](https://phlex-reactive.zoolutions.llc/docs/performance)
- Examples: [counter](https://phlex-reactive.zoolutions.llc/docs/example-counter) ·
  [chat](https://phlex-reactive.zoolutions.llc/docs/example-chat) · [todo list](https://phlex-reactive.zoolutions.llc/docs/example-todo-list) ·
  [inline edit](https://phlex-reactive.zoolutions.llc/docs/example-inline-edit) ·
  [notifications](https://phlex-reactive.zoolutions.llc/docs/example-notifications)

## Credits & prior art

The mental model is stolen, gratefully, from
[Laravel Livewire](https://livewire.laravel.com) (public method = action) and
[Phoenix LiveView](https://www.phoenixframework.org) (a component is a re-render
unit). The transport and reliability come from
[pgbus](https://github.com/mhenrixon/pgbus). The rendering is all
[Phlex](https://www.phlex.fun).

## License

[MIT](LICENSE.txt).
