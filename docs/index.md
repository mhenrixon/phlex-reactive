---
title: Home
layout: home
nav_order: 1
---

# phlex-reactive
{: .fs-9 }

Reactive [Phlex](https://www.phlex.fun) components for Rails — Livewire-style
actions and live cross-tab updates, without writing Stimulus controllers or
hand-picking Turbo Stream targets.
{: .fs-6 .fw-300 }

[Get started](installation){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/mhenrixon/phlex-reactive){: .btn .fs-5 .mb-4 .mb-md-0 }

---

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
route. No hand-picked target.**

## Why phlex-reactive

- **Actions are Ruby methods.** Declare `action :increment`; the client calls it.
- **Re-render is auto-targeted.** A component owns a stable `id`; by default the
  response replaces it — an action can return `reply.morph` / `reply.remove` /
  `reply.redirect` / `reply.replace.flash(...)` instead. You never pick a target.
- **Actions control the reply.** Return `reply.<verb>` to morph, remove, redirect
  (`Turbo.visit`), or attach a flash — or emit several streams at once. Returning
  nothing keeps the auto-replace default.
- **One unit for clicks AND broadcasts.** The same component re-renders for a
  local action and a server-pushed live update.
- **State lives in your database**, behind a signed identity — no
  attacker-controlled snapshot.
- **One tiny client runtime.** A single generic Stimulus controller, registered
  once, drives every reactive component.

Pair it with [pgbus](https://github.com/mhenrixon/pgbus) for transactional,
reconnect-safe live updates over Postgres — no Action Cable, no Redis.

## Documentation

- [Installation](installation)
- [Architecture & mental model](architecture)
- [Security & threat model](security)
- [Broadcasting & live updates](broadcasting)
- [Transport: pgbus vs Action Cable](transport-pgbus)
- [Testing](testing)

### Examples

- [Counter](examples/counter)
- [Cross-tab chat](examples/chat)
- [Live todo list](examples/todo_list)
- [Inline edit](examples/inline_edit)
- [Notifications / badges](examples/notifications)
