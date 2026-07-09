# frozen_string_literal: true

# Zeitwerk resolves this compact reference through the directory-implied
# namespaces (app/views/docs/pages/ → Views::Docs::Pages), so there's no need
# for the 4-level nested-module ceremony.
module Views
  module Docs
    module Pages
      class Effects < DocsUI::Page
        title 'Effects'
        eyebrow 'Guide'
        description 'Animate enter, exit, and update on every reactive stream render — ' \
                    'opt-in globally, per component, or per call.'

        def lead = 'Make the reactivity visible: rows fade in and out of existence and updates flash — with zero app JS.'

        def content
          try_it
          three_levels
          hooks_section
          built_ins
          custom_legs
          semantics
          accessibility_and_wire
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              Pick a style, then **Flash** the card (an `update` effect on a
              `reply.replace`), **Add row** (an `enter` effect riding the append),
              and dismiss a row (its `exit` runs *before* the element leaves the
              DOM). Every trigger here uses the per-call `effect:` form with the
              picked style held in signed state.
            MD
            render Views::Examples::LiveExample.new(
              component: EffectsGalleryComponent.new,
              filename: 'app/reactive_components/effects_gallery_component.rb'
            )
          end
        end

        def three_levels
          DocsUI::Section('Three opt-in levels', description: 'Most specific wins; off by default.') do
            md <<~MD
              Effects are **off unless you opt in** — with them off the rendered
              wire is byte-identical to previous releases.

              ```ruby
              # 1. GLOBAL — setting it is the opt-in AND the app-wide default set:
              Phlex::Reactive.effects = true   # { enter: :fade, exit: :fade, update: :highlight }
              Phlex::Reactive.effects = { enter: :slide, exit: :fade, update: :highlight }

              # 2. PER COMPONENT — refine the global set, or opt in standalone:
              class Notifications::Row < ApplicationComponent
                reactive_effects enter: :slide, exit: :fade
                # reactive_effects update: false   # disable one hook
                # reactive_effects false           # opt this component out entirely
                # reactive_effects enter: :random  # a random built-in per application
              end

              # 3. PER CALL — override one stream:
              reply.remove(effect: :shake)
              reply.append(item, to: :items, effect: :scale)
              Item.replace(@todo, effect: false)   # suppress a declared effect once
              Row.broadcast_to(@list, :todos, append: todo, target: 'rows', effect: :slide)
              ```

              A component-level declaration works without the global switch —
              declaring `reactive_effects` on a component *is* that component's
              opt-in. Unknown effect names raise at class load (never at click
              time), and the client warns-and-skips anything it doesn't recognize —
              the same two-sided default-deny as every other wire surface.
            MD
          end
        end

        def hooks_section
          DocsUI::Section('The three hooks') do
            md <<~MD
              Each hook maps to the Turbo Stream actions that mean "something
              entered / left / changed":

              | Hook | Stream actions | When it runs |
              |------|----------------|--------------|
              | `enter` | `append`, `prepend` | after render, on the arriving element |
              | `exit` | `remove` | **before** the element leaves — the removal waits for the animation |
              | `update` | `replace`, `update` (plain or morph) | after render, on the fresh root |

              Effects fire for the actor's own reply **and** for broadcasts alike —
              one interceptor covers both delivery paths, identically on Action
              Cable and pgbus. If a debounced-save grid flashes too much, turn that
              one hook off where it's noisy: `reactive_effects update: false`.
            MD
          end
        end

        def built_ins
          DocsUI::Section('Built-ins (shipped CSS)') do
            md <<~MD
              Link the engine stylesheet once:

              ```erb
              <%= stylesheet_link_tag "phlex/reactive/effects" %>
              ```

              Five named effects work on every hook: `:fade`, `:slide`, `:scale`,
              `:highlight` (the classic background flash), and `:shake`. `:random`
              picks one per application — every update animates differently (great
              for demos). Tune them with CSS custom properties:

              ```css
              :root {
                --reactive-fx-duration: 200ms;
                --reactive-fx-highlight-color: rgb(186 230 253 / 0.5);
              }
              ```
            MD
            DocsUI::Callout(:tip) do
              md <<~MD
                Keep durations comfortably under one second — the client hard-caps
                any effect wait at 1000 ms, so an exit longer than that is removed
                mid-animation.
              MD
            end
          end
        end

        def custom_legs
          DocsUI::Section('Custom effects (class legs)') do
            md <<~MD
              Skip the stylesheet entirely with named class legs — the same
              `{ during:, from:, to: }` vocabulary `js.toggle(transition:)` uses,
              perfect for Tailwind utilities. `during` classes apply for the whole
              animation; `from` swaps to `to` on the next frame:

              ```ruby
              reactive_effects enter: { during: %w[transition-all duration-300],
                                        from: %w[opacity-0 translate-y-2],
                                        to: %w[opacity-100 translate-y-0] }
              ```
            MD
          end
        end

        def semantics
          DocsUI::Section('Exit-before-removal semantics') do
            md <<~MD
              A `remove` with an exit effect keeps the element in the DOM while the
              animation runs and only then lets Turbo remove it. Three guarantees
              make that safe:

              - the wait is settled by `animationend`/`transitionend` **or** a
                timeout just past the computed duration — an interrupted animation
                can't hang the removal;
              - a **zero computed duration** (the effects stylesheet isn't loaded,
                or reduced motion zeroed it) skips the wait entirely — a missing
                `stylesheet_link_tag` never freezes deletes;
              - everything is hard-capped at 1000 ms.

              Rapid successive updates restart the flash (the class is removed,
              a reflow forced, and re-added), so a busy row keeps signalling.
            MD
          end
        end

        def accessibility_and_wire
          DocsUI::Section('Reduced motion & the wire') do
            md <<~MD
              `prefers-reduced-motion: reduce` disables effects twice over: the
              client interceptor skips them, and the shipped CSS lives inside a
              `no-preference` media query — so even a hand-built class can't animate
              against the user's setting.

              On the wire, the resolved hooks ride the component root as
              `data-reactive-effect-enter/exit/update` attributes (omitted entirely
              when off), and a per-call override rides the `<turbo-stream>` element
              itself as `data-reactive-effect` (`"off"` suppresses). Values are
              effect *names* or class lists — identity and presentation, never
              state, and the client treats them as `classList` input only.
            MD
          end
        end
      end
    end
  end
end
