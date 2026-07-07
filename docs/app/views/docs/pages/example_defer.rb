# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleDefer < DocsUI::Page
        title 'Example: deferred totals (reply.defer)'
        eyebrow 'Examples'
        description 'Defer a deliberately slow Phlex rollup with reply.defer in Rails: instant cheap streams, a pending shimmer or skeleton, and the real render streaming in when ready'

        def lead
          'A reps logger whose set count updates instantly while a deliberately ' \
            'slow session-totals rollup (~400 ms) streams in when ready — ' \
            'keep-content shimmer, skeleton, and the synchronous baseline to feel ' \
            'the difference. The totals also lazy-mount on page load.'
        end

        def content
          try_it
          the_slow_rollup
          what_each_reply_emits
          styling
          notes
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              The totals below sleep **400 ms** in their template — a stand-in for a
              genuinely expensive cross-aggregate rollup. Click and compare:

              - **Log set** — the set count bumps *instantly*; the stale totals stay
                visible, dimmed (`data-reactive-defer-pending`), until the real
                render streams in.
              - **Log set (skeleton)** — `placeholder: true` replaces the totals with
                the component's `deferred_placeholder` shell immediately.
              - **Log set (sync)** — the deliberate anti-example: the same rollup
                rendered synchronously (`also`), so the **whole** reply —
                set count included — freezes for the 400 ms the deferred variants
                take off the critical path.

              Click **Log set** rapidly: each new action *supersedes* the in-flight
              deferred render, so the totals paint once, with the final value — never
              a stale intermediate. And reload the page to watch the **lazy mount**:
              the totals are `reactive_lazy`, so the page ships a placeholder shell
              and the first render streams in on connect.
            MD
            render Views::Examples::LiveExample.new(
              component: DeferDemoComponent.new,
              filename: 'app/components/defer_demo_component.rb'
            )
          end
        end

        def the_slow_rollup
          DocsUI::Section('The slow rollup') do
            md <<~MD
              The deferred component is an ordinary reactive component. Two things
              make it defer-friendly: `deferred_placeholder` (the skeleton content
              `placeholder: true` and the lazy shell pick up) and `reactive_lazy`
              (the first page-embedded render ships the shell instead of paying the
              400 ms on page render — the client fetches the real totals on
              connect). Note the timestamp in its template: every arrival is a fresh
              server render, rebuilt from the **signed identity** in the defer token.
            MD
            DocsUI::Code(slow_rollup_source, lexer: :ruby, filename: 'app/components/session_totals_component.rb')
          end
        end

        def what_each_reply_emits
          DocsUI::Section('What each reply emits') do
            md <<~MD
              `log_set` returns:

              ```ruby
              reply.streams(sets_stream).defer(SessionTotalsComponent.new(sets: @sets))
              ```

              The actor's HTTP reply carries the cheap count update, the driver's
              token refresh, and a tiny **defer directive** — rendered only after
              the action's transaction committed, so a rollback leaks nothing. The
              directive holds a purpose-scoped, short-TTL signed token; the client
              POSTs it to `/reactive/defer` **in parallel** (off the action queue),
              and the endpoint rebuilds the component from its verified identity,
              renders it (the 400 ms happens *here*, off the critical path), and
              returns the replace stream. The arrival carries a fresh action token,
              so the totals land interactive.

              `placeholder: true` additionally emits a replace of the target with
              the pending shell *before* the directive, so the skeleton paints
              first. On a pgbus + ActiveJob stack the same directive can ride the
              push lane instead (a durable one-shot stream and a render job) — the
              Ruby above is identical either way. See the
              [Deferred rendering](/docs/deferred-rendering) guide for the lanes,
              failure handling, and the security model.
            MD
          end
        end

        def styling
          DocsUI::Section('Styling the pending window — pure CSS') do
            md <<~MD
              The client marks the wait; CSS does the rest. No Stimulus, no bespoke
              JavaScript — the demo's entire shimmer is:

              ```css
              /* keep-content default: dim the stale totals while pending */
              [data-reactive-defer-pending] { opacity: .5; transition: opacity .15s ease; }

              /* the placeholder shell (placeholder: true and the lazy mount) */
              .reactive-defer-placeholder { animation: defer-pulse 1.2s ease-in-out infinite; }
              @keyframes defer-pulse { 50% { opacity: .35; } }
              ```

              Every pending target also carries `aria-busy="true"`, so assistive
              tech knows the region is loading. A failed fetch clears the pending
              markers and sets `data-reactive-error="defer"` — style that hook too
              if you defer anything critical.
            MD
          end
        end

        def notes
          DocsUI::Section('Notes') do
            DocsUI::Callout(:warning) do
              md <<~MD
                The 400 ms sleep is the demo's stand-in for a rollup that is
                *genuinely* expensive. If your slow segment is slow because of an
                N+1 or a missing eager-load, **fix the query** — don't defer it.
                [Profile first](/docs/deferred-rendering).
              MD
            end
            DocsUI::Callout(:tip) do
              md <<~MD
                This docs site runs the pull (`fetch`) lane — the universal one that
                needs nothing but the gem's own endpoint. The demo behaves
                identically on the pgbus push lane; `defer_transport :auto` picks
                per capability at runtime.
              MD
            end
          end
        end

        # The slow component's own source, read live off its file (the LiveExample
        # pattern) so the docs can never drift from the code they demonstrate.
        def slow_rollup_source
          path = SessionTotalsComponent.instance_method(:view_template).source_location&.first
          path ? File.read(path).strip : '# source unavailable'
        end
      end
    end
  end
end
