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
              - **Accessible drawer:** `js.toggle("#ct-drawer", transition: [...])`
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
              field's value to **decide** show vs hide. `reactive_show` (#161) covers
              exactly that gap, the Alpine `x-show` / Datastar `data-show` / Livewire
              `wire:show` case: spread it onto the element to show/hide, name the
              controlling field, declare **one literal predicate** — and the generic
              controller toggles the `hidden` attribute from the field's current
              value on every `input`/`change`. Still client-only: no token, no POST.

              ```ruby
              div(**reactive_show(:mode, not: "off"))        { "shipping details" }
              div(**reactive_show(:gift, equals: true))      { "gift message" }    # checkbox: checked
              div(**reactive_show(:delivery, equals: "ship")) { "address fields" } # radio: checked value
              div(**reactive_show(:size, in: %w[l xl]))      { "surcharge note" }
              ```

              The predicate is a **declared literal match** — `equals:`, `not:`, or
              `in:` (a list) — never an expression, so there is no eval surface.
              Exactly one predicate is enforced loudly at render; extra attrs
              deep-merge through the helper. Render the initial `hidden:` yourself
              from the same server state that renders the field, so the first paint
              doesn't flash.
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
