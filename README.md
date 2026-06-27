# phlex-reactive

[![CI](https://github.com/mhenrixon/phlex-reactive/actions/workflows/main.yml/badge.svg)](https://github.com/mhenrixon/phlex-reactive/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/phlex-reactive)](https://rubygems.org/gems/phlex-reactive)
[![Docs](https://img.shields.io/badge/docs-mhenrixon.github.io-blue)](https://mhenrixon.github.io/phlex-reactive)

**Reactive [Phlex](https://www.phlex.fun) components for Rails — Livewire-style
actions and live cross-tab updates, without writing Stimulus controllers or
hand-picking Turbo Stream targets.**

📖 **[Full documentation](https://mhenrixon.github.io/phlex-reactive)**

```ruby
class Counter < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :increment
  action :decrement

  def initialize(count: 0) = @count = count
  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1

  def view_template
    div(id:, **reactive_attrs) do
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
[docs/installation.md](docs/installation.md).
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
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: { title: :string }

  def initialize(todo:) = @todo = todo
  def id = dom_id(@todo)            # stable per-record DOM id == Turbo target

  def toggle
    authorize! @todo, :update?      # YOU authorize — the token only proves identity
    @todo.toggle!(:done)
  end

  def rename(title:)
    authorize! @todo, :update?
    @todo.update!(title:)
  end

  def view_template
    li(id:, **reactive_attrs, class: ("done" if @todo.done?)) do
      button(**on(:toggle)) { @todo.done? ? "✓" : "○" }
      span { @todo.title }
    end
  end
end
```

### 2. State-backed (signed instance vars)

Sign small, JSON-serializable instance vars into the token. Use it **alone** for
a record-less widget (a counter, a wizard step), or **alongside `reactive_record`**
to carry transient UI state — which field, what mode — next to the row. Both the
record's GlobalID and the state are signed into one token and rebuilt on each
action. Keep state small and JSON-serializable.

```ruby
reactive_state :count, :step       # signed; rebuilt on each action
```

The [inline edit example](docs/examples/inline_edit.md) combines both: a
`reactive_record :record` plus `reactive_state :attribute, :editing`.

---

## Concrete examples

| Example | What it shows |
|---|---|
| [Counter](docs/examples/counter.md) | State-backed, the smallest reactive component |
| [Cross-tab chat](docs/examples/chat.md) | Record-backed action **+ pgbus broadcast** → live sync across tabs/browsers |
| [Live todo list](docs/examples/todo_list.md) | Per-row components, add/toggle/rename/delete, broadcast on change |
| [Inline edit](docs/examples/inline_edit.md) | Show ↔ edit mode toggle, replacing a Stimulus controller + 3 routes |
| [Notifications / badges](docs/examples/notifications.md) | Pure broadcast (no client action) — a job pushes a re-render |

The cross-tab chat in ~60 lines of Ruby (and zero JS) is the showcase — see
[docs/examples/chat.md](docs/examples/chat.md).

---

## API reference

### `Phlex::Reactive::Streamable`

| Method | Use |
|---|---|
| `#id` (you implement) | Stable DOM id == Turbo Stream target. Must match the root element's `id`. |
| `.replace(model = nil, morph: false, **opts)` | `<turbo-stream action=replace target=id>` of a freshly built component; `morph: true` adds `method="morph"` |
| `.update` / `.append(target:)` / `.prepend(target:)` / `.remove` | The other Turbo Stream actions |
| `.broadcast_replace_to(*streamables, model:, morph: false)` | Broadcast a replace over the stream transport (pgbus SSE / Action Cable); `morph: true` morphs in place |
| `.broadcast_append_to(*streamables, target:, model:)` / `_update_` / `_prepend_` / `_remove_` | The broadcast variants |
| `#to_stream_replace` / `#to_stream_morph` / `#to_stream_update` / `#to_stream_remove` | Stream the *already-built* instance (used internally after an action / by `reply`); `#to_stream_morph` morphs in place |

Use in controllers: `render turbo_stream: Counter.replace(counter)`.

### `Phlex::Reactive::Component`

| Macro / helper | Use |
|---|---|
| `reactive_record :name` | Record-backed identity (GlobalID). State = the DB. |
| `reactive_state :a, :b` | Signed instance-var identity. Standalone, or combined with `reactive_record` to sign transient UI state alongside the row. |
| `action :name, params: { x: :integer }` | Declare a client-invokable action + its param schema. **Default-deny.** |
| `reactive_attrs` | Spread onto the root element: marks it reactive + carries the signed token. |
| `on(:action, event: "click", **params)` | Spread onto a trigger element. Adds `type=button` for clicks. |
| `on(:action, event: "input", debounce: 300)` | Coalesce rapid events into one round trip after a quiet period (live-as-you-type). |
| `reactive_input(:param, **attrs)` / `reactive_select(:param, **attrs)` | Render a control already bound to an action param (no magic `name:`). |
| `reactive_field(:param, **attrs)` | The attribute hash behind the above — spread onto any control. |
| `nested_update!(:assoc, attrs)` | Map a nested param onto `<assoc>_attributes` with id preservation; update the record. |
| `reply.replace` / `.morph` / `.update` / `.remove` / `.redirect(url)` / `.with(*)` | Return from an action to control the reply (flash, remove, redirect, multi-stream). See [Controlling the action's reply](#reply--controlling-the-actions-reply). |

Param types: `:string` (default), `:integer`, `:float`, `:boolean`. Anything not
in the schema is dropped before reaching your method.

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

**Combining `on(...)` / `reactive_attrs` with your own attributes.** Both return
a hash that includes a `data:` key. Spreading them *and* passing another `data:`
(or `class:`, `id:`) would clobber it — use Phlex's `mix` to deep-merge:

```ruby
# ✅ merges cleanly (data-action survives, your data-testid/class are added)
button(**mix(on(:increment), class: "btn", data: { testid: "inc" })) { "+" }
div(**mix(reactive_attrs, id:, class: "card")) { ... }

# ❌ the extra data: overwrites on()'s data:, so the action never binds
button(**on(:increment), data: { testid: "inc" }) { "+" }
```

**Binding inputs to action params (drop the magic `name:`).** A field's value
travels with an action only if its `name` equals the param. Hand-writing
`name: "value"` on every input is easy to forget — the action then silently gets
nothing. `reactive_input`/`reactive_select` emit the binding for you (the trigger
stays on the button, so focusing the field doesn't dispatch and collapse edit
mode):

```ruby
action :save, params: { value: :string, status: :string }

def view_template
  span(id:, **reactive_attrs) do
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
```

| Builder | Reply |
|---|---|
| `reply.replace` / `reply.update` | re-render in place (default; `replace` is an outerHTML swap, `update` morphs inner HTML) |
| `reply.morph` / `reply.replace(morph: true)` | re-render in place via Idiomorph (`method="morph"`) — preserves the focused `<input>` + caret; for per-field reactive editing (issue #28) |
| `.also_update(target, html:)` | also re-render a companion element by DOM id; `html` is a plain string (escaped) or a Phlex component |
| `.also_replace(component, morph: false)` | also re-render another Streamable component, targeting its own `#id`; `morph: true` morphs it in place |
| `.flash(level, content, target: …)` | append a flash; `content` is a plain string (escaped) or a Phlex component (off-request — no Rails `flash`); target defaults to `Phlex::Reactive.flash_target` (`"flash"`) |
| `reply.remove` | remove the element (backed by `Streamable#to_stream_remove`) |
| `reply.redirect(url)` | client-side `Turbo.visit` (pass a `*_url`); rides a `reactive:visit` turbo-stream, not an HTTP 3xx |
| `reply.with(*streams)` / `#stream(*more)` | multi-stream |

`.flash`/`.stream`/`.also_*` are additive on a self-replace, so the component's
signed token always refreshes.

> **Under the hood.** `reply.<verb>` returns a `Phlex::Reactive::Response` — the
> immutable value object the endpoint reads. You can build one directly
> (`Phlex::Reactive::Response.replace(self)`) and it still works, but `reply` is
> the preferred surface; treat `Response` as an internal detail.

> **`html:`/`content` escaping.** A plain string is **HTML-escaped** by Turbo, so
> `html: @account.name` is safe even for user-supplied values. To emit intentional
> markup, pass a **Phlex component** (`html: Heading.new(name: @record.name)`) —
> rendered and auto-escaped through the renderer — or an `html_safe` string for
> raw HTML you control.

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

See [docs/security.md](docs/security.md) for the threat model and a checklist.

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
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :counter
  action :increment
  action :decrement

  def initialize(counter:) = @counter = counter
  def id = dom_id(@counter)

  def increment = @counter.increment!(:value)
  def decrement = @counter.decrement!(:value)

  def view_template
    div(id:, **reactive_attrs) do
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

See [docs/broadcasting.md](docs/broadcasting.md) and
[docs/transport-pgbus.md](docs/transport-pgbus.md).

---

## Documentation

- [Installation & bundler setups](docs/installation.md)
- [Mental model & architecture](docs/architecture.md)
- [Security & threat model](docs/security.md)
- [Broadcasting & live updates](docs/broadcasting.md)
- [Transport: pgbus vs Action Cable](docs/transport-pgbus.md)
- [Testing reactive components](docs/testing.md)
- Examples: [counter](docs/examples/counter.md) ·
  [chat](docs/examples/chat.md) · [todo list](docs/examples/todo_list.md) ·
  [inline edit](docs/examples/inline_edit.md) ·
  [notifications](docs/examples/notifications.md)

## Credits & prior art

The mental model is stolen, gratefully, from
[Laravel Livewire](https://livewire.laravel.com) (public method = action) and
[Phoenix LiveView](https://www.phoenixframework.org) (a component is a re-render
unit). The transport and reliability come from
[pgbus](https://github.com/mhenrixon/pgbus). The rendering is all
[Phlex](https://www.phlex.fun).

## License

[MIT](LICENSE.txt).
