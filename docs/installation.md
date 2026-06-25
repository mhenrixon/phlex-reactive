---
layout: default
title: Installation
nav_order: 2
---

# Installation

```ruby
# Gemfile
gem "phlex-reactive"
```

```bash
bundle install
bin/rails generate phlex:reactive:install
```

The Rails engine automatically:

- mounts `POST /reactive/actions` → `Phlex::Reactive::ActionsController#create`
- adds the gem's `app/javascript` to the asset paths
- auto-pins (and `preload: true`s) the client controller for importmap apps

The **installer** (`phlex:reactive:install`) does the host-app wiring:

- registers the `reactive` Stimulus controller eagerly in your entrypoint
- writes `config/initializers/phlex_reactive.rb` with the common options

If you'd rather wire it by hand, register the controller once (eagerly — below).

## Generators

```bash
# Setup (idempotent)
bin/rails generate phlex:reactive:install

# Scaffold a state-backed component (record-less)
bin/rails generate phlex:reactive:component Counter increment decrement

# Scaffold a record-backed component (signed GlobalID identity)
bin/rails generate phlex:reactive:component Todos::Item toggle rename --record todo

# Custom signed state vars
bin/rails generate phlex:reactive:component Wizard next_step --state step open
```

The component generator also writes an RSpec spec when your app has a `spec/`
directory.

## importmap-rails (default Rails 7+)

```js
// app/javascript/controllers/index.js
import { application } from "controllers/application"
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

**Register eagerly, not lazily.** If you `lazyLoadControllersFrom`, the
controller is fetched on first appearance — and a user who clicks immediately
after load can fire before it connects, so nothing happens. Eager registration
(above) guarantees it's bound before any interaction. The engine already
preloads the asset, so this adds no latency.

## esbuild / rollup / webpack (jsbundling)

```js
// app/javascript/controllers/index.js
import { application } from "./application"
import ReactiveController from "phlex-reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

If your bundler can't resolve the gem path, copy the file in:

```bash
cp "$(bundle show phlex-reactive)/app/javascript/phlex/reactive/reactive_controller.js" \
   app/javascript/controllers/reactive_controller.js
```

…and `import ReactiveController from "./reactive_controller"`.

Importing `reactive_controller.js` also registers the `reactive:visit` Turbo
`StreamAction` that powers `Response.redirect`. The `import ReactiveController`
above covers this; if you vendor the file, make sure it's actually imported (not
tree-shaken away) or redirects won't fire.

## bun (bun-rails)

Same as esbuild. Point the import at the gem path or vendor the file.

## Requirements

- **Rails** ≥ 7.1
- **Phlex 2** via `phlex-rails`, with an `ApplicationComponent < Phlex::HTML`
  base class that includes the Phlex Rails helpers (`dom_id`, `t`, routes, etc.)
- **Turbo** ≥ 8 (for morphing) — `turbo-rails`, with `window.Turbo` available
- **A `<meta name="csrf-token">`** in your layout (standard Rails)
- **pgbus** (optional, recommended) for reliable broadcasting

## Configuration

Create `config/initializers/phlex_reactive.rb` as needed:

```ruby
Phlex::Reactive.base_controller_name = "ApplicationController"   # CSRF + auth + Current
Phlex::Reactive.renderer             = ApplicationController     # app helpers during render
Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
# Phlex::Reactive.action_path = "/_r/actions"                   # custom endpoint
# Phlex::Reactive.verifier    = ActiveSupport::MessageVerifier.new(ENV["REACTIVE_KEY"])
# Phlex::Reactive.flash_target = "flash"                         # DOM id Response#flash appends into
```

If you change `action_path`, expose it to the client:

```erb
<meta name="phlex-reactive-action-path" content="<%= Phlex::Reactive.action_path %>">
```

## Verify it works

Drop a counter (see [examples/counter.md](examples/counter.md)) on any page,
click `+`, and watch it increment with no full-page reload. If it reloads or does
nothing, see [testing.md](testing.md#troubleshooting).
