# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleLoadingStates < DocsUI::Page
        title 'Example: loading states'
        eyebrow 'Examples'
        description 'Add Livewire-style loading states to reactive Phlex actions in Rails with disable_with, busy_on, and aria-busy CSS hooks that dedupe double-submits'

        def lead
          'Declarative pending affordances — `disable_with:` swaps a button label ' \
            'and disables it in flight, `busy_on` reveals a scoped spinner, and the ' \
            'always-on `aria-busy` / `data-reactive-busy` hooks let you style the ' \
            'wait with pure CSS. No Stimulus, no bespoke JavaScript.'
        end

        def content
          try_it
          disable_with
          busy
          double_submit
          notes
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              A localhost round trip is ~5 ms — the pending window flashes by
              before you can see it. **Flip the toggle on** and every reactive
              action is delayed client-side, so the affordances below become
              observable. It's a pure client concern: no token, no POST.
            MD
            render Views::Examples::LatencyToggle.new(delay_ms: 500)
            render Views::Examples::LiveExample.new(
              component: LoadingButtonComponent.new(count: 0),
              filename: 'app/components/loading_button_component.rb'
            )
          end
        end

        def disable_with
          DocsUI::Section('disable_with: — swap the label, disable in flight') do
            md <<~MD
              `on(:save, disable_with: "Saving…")` swaps the button's text and
              disables it the instant the request is enqueued, reverting when the
              round trip settles. It's the shorthand for
              `loading: { disable: true, text: "Saving…" }` — Livewire's
              `wire:loading` + `phx-disable-with` without a Stimulus controller.
            MD
          end
        end

        def busy
          DocsUI::Section('busy_on — a scoped spinner, styled with CSS') do
            md <<~MD
              `busy_on(:save)` puts `data-reactive-busy` on an element ONLY while
              `save` is in flight. Reveal it with pure CSS — here daisyUI's
              `loading loading-spinner` — no Ruby toggles it. Every reactive root
              also always carries `aria-busy="true"` during any in-flight action,
              so you can style the whole component's wait state with an
              attribute selector.
            MD
          end
        end

        def double_submit
          DocsUI::Section('No double-submit — the disable IS the dedup') do
            md <<~MD
              With the latency simulator on, click **Save** twice quickly: the
              count still advances by **one**. A disabled button fires no further
              clicks, so the second press lands on a dead control and never
              enqueues a second POST. The client queue serializes requests per
              component; `disable_with:` is what dedupes them.
            MD
          end
        end

        def notes
          DocsUI::Section('Notes') do
            DocsUI::Callout(:tip) do
              md <<~MD
                The latency toggle is a docs convenience, not a gem feature you
                ship. In your own app the simulator is exposed on
                `window.PhlexReactive.enableLatencySim(ms)` when you author
                `<meta name="phlex-reactive-env" content="development">` — see
                [Installation](/docs/installation). Production stays untouched.
              MD
            end
          end
        end
      end
    end
  end
end
