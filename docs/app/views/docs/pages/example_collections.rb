# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleCollections < DocsUI::Page
        title 'Example: reactive collections'
        eyebrow 'Examples'
        description 'Build add/remove-row reactive collections in Rails Phlex: declare append, remove, count, and empty-state once, with optimistic dismiss and cross-tab sync'

        def lead
          'An add/remove-row list — line items, attachments, tags, a notifications ' \
            'feed — declares its append/remove + running count + empty-state contract ' \
            'ONCE on the container, so each action is a single `reply.append` / ' \
            '`reply.remove`. Plus optimistic dismiss and a self-dismissing flash.'
        end

        def content
          try_it
          declare_once
          the_row
          the_empty_state
          what_each_reply_emits
          notes
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              Add a notification and dismiss it. Each **add** appends the row, bumps
              the count badge, and clears the empty-state in ONE reply; each
              **dismiss** removes the row (optimistically — it hides the instant you
              click), restores the empty-state when the last one goes, and shows a
              self-dismissing toast. Turn on the latency toggle to watch the
              optimistic hide before the round trip lands.
            MD
            render Views::Examples::LatencyToggle.new(delay_ms: 600)
            render Views::Examples::LiveExample.new(
              component: NotificationsListComponent.new,
              filename: 'app/components/notifications_list_component.rb'
            )
          end
        end

        def declare_once
          DocsUI::Section('Declare the list contract once') do
            md <<~MD
              `reactive_collection` names the row component, the container DOM id, an
              optional count-badge id, an optional empty-state component, and a
              **size resolver** (a proc that reads the live count). After that, an
              action governs the reply with a single call — no hand-deriving the
              container id, the count, and the empty-state in every action.

              - `reply.append(:notifications, record)` → row stream + count + clears
                the empty-state.
              - `reply.remove(:notifications, record)` → row remove + count +
                restores the empty-state.

              The size resolver reads `Notification.count` server-side, so the badge
              is always correct — never an off-by-one client increment.
            MD
          end
        end

        def the_row
          DocsUI::Section('The row (tokenless — it dispatches the container)') do
            md <<~MD
              `NotificationRowComponent` carries **no token of its own**: its dismiss
              button dispatches the *container's* `dismiss` action (keyed by the
              record id) via the generic controller it sits inside. That's why a
              streamed-in row (via `reply.append`) is fully interactive without any
              re-wiring. `optimistic: { hide: true }` hides the row the instant you
              click; `reply.remove` then drops it, so it never flashes back.
            MD
            DocsUI::Code(read_component('notification_row_component.rb'),
                         lexer: :ruby, filename: 'app/components/notification_row_component.rb')
          end
        end

        def the_empty_state
          DocsUI::Section('The empty-state') do
            md <<~MD
              A static Streamable component with a stable `#id`. The collection helper
              removes it by that id when the first row is added and appends it back
              when the last row is dismissed — you never toggle it by hand.
            MD
            DocsUI::Code(read_component('notifications_empty_component.rb'),
                         lexer: :ruby, filename: 'app/components/notifications_empty_component.rb')
          end
        end

        def what_each_reply_emits
          DocsUI::Section('What each reply emits') do
            md <<~MD
              One `reply.append` / `reply.remove` expands into a **multi-stream**
              turbo reply: the row (append/remove), the count companion (replace),
              and the empty-state (remove/append). `dismiss` chains a
              `.flash(:notice, "…", dismiss_after: 3000)` so a toast appears in the
              `#flash` region and clears itself after 3 s — no timer in your Ruby.
              Every mutation also broadcasts to the other tabs with
              `exclude: reactive_connection_id`, so a second window stays in sync.
            MD
          end
        end

        def notes
          DocsUI::Section('Notes') do
            DocsUI::Callout(:tip) do
              md <<~MD
                `count:` and `empty:` are optional — a list with just rows omits them
                and those streams simply aren't emitted. The row component owns its
                own actions; the collection is only about the container-level
                add/remove reply. See
                [Broadcasting & live updates](/docs/broadcasting).
              MD
            end
          end
        end

        # Read a reactive component's own source off disk so the code shown here can
        # never drift from the components the demo renders.
        def read_component(basename)
          Rails.root.join('app/reactive_components', basename).read.strip
        end
      end
    end
  end
end
