# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExamplesOverview < DocsUI::Page
        title 'Examples'
        eyebrow 'Examples'

        def lead
          'Concrete, copy-pasteable examples covering the common patterns. ' \
            'Each is a complete, working feature — with the live reactive ' \
            'component rendered on its page, not a screenshot.'
        end

        # One section only — an overview index stays scannable, and the auto-TOC
        # deliberately hides on a page with too few sections (see the system
        # spec). The two tables (the examples + the by-feature map) live under the
        # single heading so no TOC is triggered.
        def content
          DocsUI::Section('The examples') do
            md <<~MD
              Each page below is a complete, working feature you can copy and
              paste. They build from the smallest reactive component up to
              record-backed actions, live broadcasts, and declared-once
              collections — and each renders its **real** reactive component
              inline so you can click it.

              | Example | What it shows |
              |---|---|
              | [Counter](/docs/example-counter) | State-backed — the smallest reactive component. Click → server → re-render, no DB row. |
              | [Payment split](/docs/example-payment-split) | Live sum-to-total rebalancer: nested bracketed params, auto-collected siblings, a client-side `reactive_compute` total that paints before the debounced save. |
              | [Cross-tab chat](/docs/example-chat) | Record-backed action **and broadcast** → live cross-tab sync in ~60 lines of Ruby, zero JS. |
              | [Live todo list](/docs/example-todo-list) | Per-row record-backed components: add / toggle / rename / archive, Enter-to-add, morph-in-place, broadcast on change. |
              | [Inline edit](/docs/example-inline-edit) | Show ↔ edit toggle: Enter saves, Escape cancels — replacing a Stimulus controller plus three routes. |
              | [Notifications / badges](/docs/example-notifications) | Pure broadcast (no client action) — a job pushes a live re-render. |
              | [Reactive collections](/docs/example-collections) | Add / remove rows + a running count + an empty state, declared **once** with `reactive_collection`. |

              **Scanning for a specific capability** — each headline feature is
              showcased inside one of the examples above (or, for the combobox, a
              live demo). The reference docs for each live in the
              [README](https://github.com/mhenrixon/phlex-reactive#readme).

              | Feature | Where it's shown |
              |---|---|
              | **Client-only ops** — `on_client` + `js` (`show`/`hide`/`toggle`, `set_attr`/`toggle_attr`, `focus`, `dispatch`, transitions): zero round trips | [Todo list](/docs/example-todo-list), [Notifications](/docs/example-notifications) |
              | **Client-side computes** — `reactive_compute` + `reactive_text` (a running total / live preview / char counter that paints with no round trip) | [Payment split](/docs/example-payment-split) |
              | **Declarative loading states** — `loading:` / `disable_with:` / `busy_on` (+ the always-on `aria-busy` / `data-reactive-busy` you style with CSS) | [Payment split](/docs/example-payment-split), [Inline edit](/docs/example-inline-edit), [Collections](/docs/example-collections) |
              | **Dirty-field tracking** — `dirty:` / `track_dirty:` / `warn_unsaved:` (enable Save only on change; warn before leaving) | [Inline edit](/docs/example-inline-edit) |
              | **Optimistic visual hints** — `optimistic:` (flip a checkbox / hide a row the instant you click; revert on failure) | [Todo list](/docs/example-todo-list), [Collections](/docs/example-collections) |
              | **Keyboard triggers** — `event: "keydown.enter"` / `"keydown.esc"` (Enter-to-add, Escape-to-cancel) | [Todo list](/docs/example-todo-list), [Inline edit](/docs/example-inline-edit) |
              | **Debounced / morph editing** — `debounce:` live-as-you-type + `reply.morph` to keep the focused field's caret | [Payment split](/docs/example-payment-split), [Inline edit](/docs/example-inline-edit) |
              | **Live broadcasts** — `broadcast_replace_to` / `broadcast_append_to` → cross-tab sync | [Chat](/docs/example-chat), [Notifications](/docs/example-notifications), [Todo list](/docs/example-todo-list) |
              | **Combobox keyboard navigation** — `listnav:` (Arrow keys move a client highlight, Enter picks) | [Searchable combobox demo](/demos/searchable-combobox) |
            MD

            DocsUI::Callout(:note) do
              md <<~MD
                **File uploads** (`:file` params / multipart `FormData`) and
                **custom param types** (`Phlex::Reactive.param_type`) don't yet
                have a worked example page — see the
                [README](https://github.com/mhenrixon/phlex-reactive#readme) for
                the reference. The [payment split](/docs/example-payment-split)
                is the closest cousin: it's the nested-params / auto-collected
                sibling-fields example that a `FormData` upload extends.
              MD
            end
          end
        end
      end
    end
  end
end
