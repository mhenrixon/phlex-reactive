# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleFailure < DocsUI::Page
        title 'Example: failure surface'
        eyebrow 'Examples'

        def lead
          'Reactive actions don’t only succeed. This shows what an adopter gets for ' \
            'free when one fails: a server-rendered flash (`error_flash`), a ' \
            '`data-reactive-error` hook you style with CSS, and self-dismissing ' \
            'toasts (`dismiss_after:`).'
        end

        def content
          try_it
          error_flash
          error_hook
          timeout
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              Click **Trigger a failure** — the action denies server-side (a declared
              authorization error → 403). The endpoint renders a flash the browser
              shows, and the root gets `data-reactive-error="http"`, which reveals the
              error banner via pure CSS. **Succeed** clears it. **Self-dismissing
              flash** shows a toast that removes itself after `dismiss_after:`.
            MD
            render Views::Examples::LatencyToggle.new(delay_ms: 500)
            render Views::Examples::LiveExample.new(
              component: FailureSurfaceComponent.new(count: 0),
              filename: 'app/components/failure_surface_component.rb'
            )
          end
        end

        def error_flash
          DocsUI::Section('Server-rendered failure flashes (error_flash)') do
            md <<~MD
              Set `Phlex::Reactive.error_flash = ->(kind) { "…" }` and the action
              endpoint renders a turbo-stream flash into your `flash_target` whenever
              an action fails — a denied action (403, `kind: "http"`), a timeout
              (`kind: "timeout"`), or a network error (`kind: "offline"`). You write
              the copy; the framework surfaces it. It's opt-in: with `error_flash`
              unset, failures are silent (the client still sets `data-reactive-error`).
            MD
          end
        end

        def error_hook
          DocsUI::Section('The data-reactive-error hook') do
            md <<~MD
              On any failed action the client sets `data-reactive-error="<kind>"` on
              the component root; a successful re-render clears it. Style the wait/
              failure state with a plain attribute selector — here the error banner is
              `display:none` until `[data-reactive-error]` is present. No Ruby toggles
              it, and it survives a morph because it's driven off the attribute, not
              the HTML.
            MD
          end
        end

        def timeout
          DocsUI::Section('Timeouts and offline') do
            md <<~MD
              The client aborts a request that exceeds `phlex-reactive-timeout`
              (default 30 s; set the meta lower to demo it) with
              `kind: "timeout"`, and a fetch that fails offline with
              `kind: "offline"` — both flow through the same `error_flash` +
              `data-reactive-error` surface as a 403. Crucially, the per-component
              request queue does **not** wedge: after a timeout, the next action
              still round-trips. Flip the latency simulator on to make the in-flight
              window observable.
            MD
            DocsUI::Callout(:note) do
              md <<~MD
                A live timeout needs a page-level `phlex-reactive-timeout` meta set
                below the simulated delay, which would affect every demo on the page.
                The timeout/offline behavior is covered end-to-end in the gem's own
                browser suite; here we demo the 403 → `error_flash` path, which shares
                the exact same client surface.
              MD
            end
          end
        end
      end
    end
  end
end
