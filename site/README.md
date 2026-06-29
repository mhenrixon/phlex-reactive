# phlex-reactive — interactive demo site

A Rails app that **dogfoods** [phlex-reactive](https://github.com/mhenrixon/phlex-reactive):
every demo is a real reactive component running live, with its source shown
alongside. It depends on the gem from the repo root (`gem "phlex-reactive", path: ".."`),
so the site always exercises the working tree.

> This is a separate application from the published Jekyll docs in `../docs`.
> The Jekyll site keeps publishing to GitHub Pages until this app is live; only
> then does the cutover happen.

## What's here (PR #1)

- **`SearchableComboboxComponent`** — the headline demo (issue #51): a debounced,
  state-backed combobox that filters an in-memory list with **zero custom
  JavaScript**. Typing filters via a reactive round trip; focus and caret survive
  the morph; clicking an option reports the selection back.
- A **3-tab demo panel** per example: **Demo** (live), **Call-site** (how to mount
  it), **Component** (the component's own source).
- A landing page + a per-demo route (`/demos/:slug`).

Counter / Todos / Chat demos and the ported reference docs land in PR #2.

## Running locally

```bash
cd site
bundle install
bun install && bunx playwright install chromium   # browser suite
bin/rails server                                   # http://localhost:3000
```

## Tests

```bash
bundle exec rspec spec/requests spec/system          # under Puma (default)
CAPYBARA_SERVER=falcon bundle exec rspec spec/system # under Falcon (async)
bundle exec rubocop
```

The reactive round trip is proven under **both** real servers — Puma (sync) and
Falcon (async) — exactly as the gem's own suite requires.

## How it dogfoods the gem

The phlex-reactive engine auto-mounts `POST /reactive/actions` and auto-pins the
client controller for importmap apps. The only manual wiring is registering the
controller eagerly in `app/javascript/controllers/index.js`. Reactive demo
components live at the top level in `app/reactive_components/` (no `Components::`
prefix) so their class names match what a reader would write — the signed
identity token carries the class name verbatim.
