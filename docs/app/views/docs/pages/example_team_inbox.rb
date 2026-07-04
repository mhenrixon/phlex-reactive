# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleTeamInbox < DocsUI::Page
        title 'Example: Team inbox (the flagship)'
        eyebrow 'Examples'
        description 'Build a live team inbox in reactive Phlex: reactive_collection rows, an optimistic archive that reverts on failure, cross-tab broadcasts, and error_flash'

        def lead
          'One believable UI that composes the whole toolkit: reactive_collection ' \
            'rows, an optimistic archive that reverts on failure, disable_with:, ' \
            'cross-tab broadcasts, an on_client row menu, and error_flash — with no ' \
            'Stimulus controller and no hand-picked Turbo target.'
        end

        def content
          try_it
          whats_here
          the_container
          the_row
          revert
          notes
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              A real Team inbox. **Simulate incoming** pushes a new message (and
              broadcasts it to teammates). Open a row's **⋯** menu (a pure client op)
              to **Mark read** or **Archive**. Archive hides the row instantly and
              confirms with a self-dismissing toast. Try archiving the **locked**
              message — the server refuses, so the optimistic hide **reverts** and an
              error flash explains why. Turn on the latency toggle to watch the
              optimistic hide and the `disable_with:` guard.
            MD
            render Views::Examples::LatencyToggle.new(delay_ms: 700)
            render Views::Examples::LiveExample.new(
              component: TeamInboxComponent.new,
              filename: 'app/components/team_inbox_component.rb'
            )
          end
        end

        def whats_here
          DocsUI::Section('Every feature, in one component') do
            md <<~MD
              | Feature | Where |
              |---|---|
              | **`reactive_collection`** — rows + running count + empty-state declared once | the container |
              | **Optimistic archive** — `optimistic: { hide: true }` hides the row in the same gesture | the row's Archive |
              | **Revert on failure** — a denied archive snaps the row back + shows an error flash | the "locked" message |
              | **`disable_with:`** — the Archive / Simulate buttons dedupe a double-click | container + row |
              | **Cross-tab broadcast** — `broadcast_append_to` / `broadcast_remove_to` / `broadcast_replace_to` | every mutating action |
              | **`on_client` menu** — the ⋯ kebab toggles with zero round trips | the row |
              | **`error_flash` + `dismiss_after:`** — a self-dismissing confirmation / error toast | the reply |
            MD
          end
        end

        def the_container
          DocsUI::Section('The container') do
            md <<~MD
              `TeamInboxComponent` declares the collection once and drives three
              actions. `archive` removes the row + count + empty-state in one
              `reply.remove`, broadcasts the removal to teammates, and chains a
              `.flash(dismiss_after: 2000)`. `mark_read` persists + broadcasts the
              updated row. `simulate_incoming` creates a message and
              `broadcast_append_to`s it (excluding the actor, who gets it from their
              own `reply.append`).
            MD
            DocsUI::Code(read_component('team_inbox_component.rb'),
                         lexer: :ruby, filename: 'app/components/team_inbox_component.rb')
          end
        end

        def the_row
          DocsUI::Section('The row (tokenless — client menu + container dispatch)') do
            md <<~MD
              `InboxMessageComponent` carries **no token of its own**. Its ⋯ kebab is
              a pure `on_client(:click, js.toggle(...))` — zero round trips. The
              Archive / Mark-read buttons inside dispatch the *container's* actions
              keyed by message id. Archive's `optimistic:` hint targets **this
              row's** own id (`to: "#" + dom_id`) — not `:root`, because a tokenless
              row's `:root` would hide the whole inbox — so only the archived row hides.
            MD
            DocsUI::Code(read_component('inbox_message_component.rb'),
                         lexer: :ruby, filename: 'app/components/inbox_message_component.rb')
          end
        end

        def revert
          DocsUI::Section('Optimistic revert on failure') do
            md <<~MD
              The optimistic hint is **cosmetic and always reversible**. When the
              archive of the locked message denies (a registered authorization error
              → 403), the client replays the inverse: the row that was optimistically
              hidden **snaps back**, and `error_flash` surfaces the reason. Nothing
              was persisted, and the inbox is exactly as it was — the whole point of
              an optimistic hint that can't drift from server truth.
            MD
            DocsUI::Callout(:tip) do
              md <<~MD
                This is the discipline that makes optimistic UI safe here: the hint
                is a *guess* the server confirms or reverts. You never ship state to
                the client and trust it back — the signed identity re-finds the
                record, the action authorizes, and the reply is the source of truth.
              MD
            end
          end
        end

        def notes
          DocsUI::Section('Notes') do
            md <<~MD
              Open this page in **two tabs** and archive or mark-read in one — the
              other updates live over the shared inbox stream
              (`exclude: reactive_connection_id` keeps the actor from doubling). On
              the deployed docs site this rides pgbus SSE; in dev/CI it's Action
              Cable. The component is identical either way — the transport is a
              config detail, not a code path.
            MD
          end
        end

        def read_component(basename)
          Rails.root.join('app/reactive_components', basename).read.strip
        end
      end
    end
  end
end
