# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleClientOps < DocsUI::Page
        title 'Example: client-only ops'
        eyebrow 'Examples'
        description 'Build tabs, outside-close menus, and accessible drawers with on_client — phlex-reactive runs a whitelist of local DOM ops, zero round trips, no custom JS'

        def lead
          'Some interactions never need the server — tabs, a menu that closes on an ' \
            'outside click, an accessible drawer with a transition + focus. `on_client` ' \
            'runs a whitelist of DOM ops locally, with ZERO round trips and ZERO ' \
            'custom JavaScript.'
        end

        def content
          try_it
          how
          ops
          value_conditional
          when_to_use
        end

        private

        def try_it
          DocsUI::Section('Try it — nothing here hits the server') do
            md <<~MD
              Switch tabs, open the menu (then click anywhere outside to close it),
              open the drawer (it fades in and focus lands on its first button).
              Every one of these is a client op — **no token, no POST, ever**. Open
              the network tab: you will see nothing. The component declares **no
              actions** at all.
            MD
            render Views::Examples::LiveExample.new(
              component: ClientTabsComponent.new,
              filename: 'app/components/client_tabs_component.rb'
            )
          end
        end

        def how
          DocsUI::Section('How it works') do
            md <<~MD
              `on_client(:click, ops)` binds a chain of DOM ops to an event and runs
              them locally through the one generic reactive controller. The ops are a
              **frozen whitelist** — `show`/`hide`/`toggle`, `add_class`/
              `remove_class`/`toggle_class`, `set_attr`/`toggle_attr`/`remove_attr`,
              `focus`/`focus_first`, `text`, `dispatch` — each a pure, local DOM
              mutation. Nothing is read back, nothing is sent anywhere.

              - **Tabs:** `js.hide(".ct-panel").show("#ct-panel-1")` plus class ops on
                the tab buttons — the "I had to write a Stimulus controller" case, now
                one line.
              - **Outside-close menu:** `on_client(:click, js.hide("#ct-menu"),
                outside: true)` on the **root** fires on any click *outside* the menu.
                A client op costs nothing per stray page click (unlike a server action).
              - **Accessible drawer:** `js.toggle("#ct-drawer", transition: { during:, from:, to: })`
                animates it, `set_attr(:root, "aria-expanded", "true")` updates the
                trigger, and `focus_first("#ct-drawer")` moves focus to the first
                control inside — the exact accessible-disclosure pattern, one chain.
            MD
          end
        end

        def ops
          DocsUI::Section('The op vocabulary') do
            md <<~MD
              Ops are built with the server-side `js` helper and serialized into a
              `data-reactive-ops` attribute the client interprets. An op name not on
              the whitelist is warn-and-skipped (client-side default-deny) — a stale
              or newer ops attribute can never break the page. `focus`/`focus_first`
              are allowed here (an actor's own gesture) but **rejected** from a
              broadcast, where stealing focus in every subscriber's tab would be hostile.

              `text(to, value)` (#159) sets the target's `textContent` — stringified,
              `nil` clears, **never `innerHTML`** — so a chain can paint a label or a
              derived number without a round trip. Pair it with `global: true` to
              reach a node **outside** the component's root (the cross-root text
              escape a read-only recap needs).
            MD
            DocsUI::Callout(:tip) do
              md <<~MD
                Reach for `on_client` whenever the interaction is purely presentational
                — toggling a disclosure, closing a popover, moving focus. Reach for a
                reactive `action` (a token + POST) only when the server must **decide**
                or **persist** something.
              MD
            end
          end
        end

        def value_conditional
          DocsUI::Section('Value-conditional visibility (reactive_show)') do
            md <<~MD
              `on_client` ops are *unconditional* — they can't read the triggering
              field's value to **decide** show vs hide. `reactive_show` (#180) covers
              exactly that gap, the Alpine `x-show` / Datastar `data-show` / Livewire
              `wire:show` case, in ONE Ruby-native conditions language: `if:` /
              `if_any:` / `unless:`, with `where`-style values. The generic
              controller toggles the `hidden` attribute from the fields' current
              values on every `input`/`change`. Still client-only: no token, no POST.

              A **Hash is an AND**, an **Array is membership**, a **Range is a
              threshold**, and `unless:` **negates** — the whole value vocabulary:

              ```ruby
              div(**reactive_show(unless: { mode: "off" }))            { "shipping details" }
              div(**reactive_show(if: { gift: true }))                 { "gift message" }   # checkbox checked
              div(**reactive_show(if: { delivery: "ship" }))           { "address fields" } # radio value
              div(**reactive_show(if: { size: %w[l xl] }))             { "surcharge note" } # membership
              div(**reactive_show(if: { quantity: 10.. }))             { "bulk note" }      # threshold
              ```

              Extra HTML attrs pass through unambiguously (conditions live in `if:`),
              so `div(**reactive_show(if: { size: %w[l xl] }, class: "note"))` works.

              **OR-of-AND without the distributive law.** `if_any:` takes an array of
              AND-hashes — one level of disjunction, which covers every boolean
              visibility rule. This is the case that used to force hand-applied
              distributive law encoded as nested wrapper divs:

              ```ruby
              # visible while director OR (shareholder AND role == "individual")
              div(**reactive_show(if_any: [
                { director: true },
                { shareholder: true, role: "individual" }
              ]))
              # AND across fields, with negation, in one binding:
              div(**reactive_show(if: { type: "individual" }, unless: { country: "domestic" }))
              ```

              **First paint is computed for you.** Declare `reactive_values` once and
              every binding whose fields are all provided renders the correct initial
              `hidden:` server-side — no per-section mirror method, no flash:

              ```ruby
              def reactive_values = { director: @director, role: @role, quantity: @qty }
              # …then every reactive_show computes hidden: from these, automatically.
              ```

              `reactive_scope :form` lets bindings use bare symbols while the client
              resolves `[name="form[field]"]`, and `disable: true` disables a hidden
              section's own controls so a switched-away value never submits. A blank
              or non-numeric field fails a numeric term **closed** (stays hidden) —
              the safe default. There is no expression surface: every term is a
              declared literal, the same default-deny posture as before.

              A plain `reactive_show` is root-scoped by design. When the dependents
              live **outside** the control's root — a nav tab, a panel in another
              tab pane, a sidebar note — `reactive_show_targets` (#164) is the
              declared escape: the component that **owns** the field declares which
              outside ids it governs, spread on the root, using the same `where`-style
              values. Id selectors only (raise at render, warn-and-skip on the client
              — two-sided default-deny); a target id not on the page is skipped.

              ```ruby
              div(**mix(reactive_root, reactive_show_targets(:mode,
                "#advanced-tab" => "advanced",         # equals
                "#premium-note" => %w[gold platinum])))  # membership
              ```
            MD
            render Views::Examples::LiveExample.new(
              component: ConditionalFieldsetComponent.new,
              filename: 'app/components/conditional_fieldset_component.rb'
            )
          end
        end

        def when_to_use
          DocsUI::Section('The zero-fetch contract') do
            md <<~MD
              Because the component declares no actions and every trigger is
              `on_client`, a click here never mints a token and never posts. That is
              the tested contract: the browser suite spies on `fetch` and asserts it
              is called **zero** times across every tab switch, menu toggle, and
              drawer open.
            MD
          end
        end
      end
    end
  end
end
