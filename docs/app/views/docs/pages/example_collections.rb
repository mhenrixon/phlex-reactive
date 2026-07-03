# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleCollections < DocsUI::Page
        title 'Example: collections (add/remove rows + count + empty-state)'
        eyebrow 'Examples'

        def lead
          'An add/remove-row list — line items, attachments, tags, comments, a notifications list — declares its ' \
            'append/remove + count + empty-state contract once on the container, so each action is a single call.'
        end

        def content
          intro
          declare_collection
          row_and_empty
          what_each_reply_emits
          add_to_top
          instant_feedback
          why_count_right
          repeated_add_remove
          cross_tab
          related
        end

        private

        def intro
          DocsUI::Section('Example: reactive collections (add/remove rows + count + empty-state)') do
            DocsUI::Prose() do
              p do
                plain 'An add/remove-row list — line items, attachments, tags, comments, a notifications list — is '
                plain 'one of the most common reactive surfaces. Each one re-implements the same orchestration by '
                plain 'hand in every action: append the new row to the right container, remove it on delete, keep a '
                strong { 'count badge' }
                plain ' in sync, and swap an '
                strong { 'empty-state' }
                plain ' in and out as the list crosses 0↔1. Each is easy to get subtly wrong (off-by-one badge, '
                plain 'empty-state not toggled, container id drift between the static render and the action), and '
                plain "it's duplicated per list."
              end
              p do
                code { 'reactive_collection' }
                plain ' declares that contract '
                strong { 'once' }
                plain ' on the container, so each action is a single call.'
              end
            end
          end
        end

        def declare_collection
          DocsUI::Section('Declare the collection on the container') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              class NotificationsList < ApplicationComponent
                include Phlex::Reactive::Component

                reactive_collection :notifications,
                  item: NotificationRow,          # the per-row Streamable component
                  container: "notifications",     # the DOM id rows live in
                  count: "notifications-count",   # optional companion id (the size badge)
                  empty: NotificationsEmpty,      # optional empty-state component
                  size: -> { current_user.todos.size }  # this list's live size (re-counted server-side)

                action :add, params: {title: :string}
                action :dismiss, params: {id: :integer}   # default-deny + schema-coerced to Integer

                def id = "notifications-list"

                def add(title:)
                  todo = current_user.todos.create!(title:)
                  reply.append(:notifications, todo)   # row + bump count + clear empty-state
                end

                def dismiss(id:)
                  todo = current_user.todos.find(id)   # scope the lookup + authorize BEFORE destroy!
                  authorize! todo, :destroy?
                  todo.destroy!
                  reply.remove(:notifications, todo)   # pass the RECORD → its dom_id is the remove target
                end

                def view_template
                  todos = current_user.todos.order(:created_at, :id)

                  div(**reactive_root) do
                    span(id: "notifications-count") { todos.size.to_s }

                    ul(id: "notifications") do
                      if todos.any?
                        todos.each { |t| render NotificationRow.new(todo: t) }
                      else
                        render NotificationsEmpty.new
                      end
                    end

                    div do
                      input(name: "title", placeholder: "New notification…", autocomplete: "off")
                      # disable_with: swaps the label + disables while the create is in flight,
                      # so a rapid double-click enqueues exactly one add.
                      button(**mix(on(:add, disable_with: "Adding…"))) { "Add" }
                    end
                  end
                end
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'The same three things the helper streams in and out on each delta — the row, the count, the '
                plain 'empty-state — are what '
                code { 'view_template' }
                plain ' renders on first paint, so the initial server render and the reactive deltas cannot drift.'
              end
              ul do
                li do
                  strong { 'Params are schema-coerced and default-deny.' }
                  plain ' '
                  code { 'params: {id: :integer}' }
                  plain ' coerces the client value to an Integer; anything not in the schema is dropped before '
                  plain 'reaching '
                  code { 'dismiss' }
                  plain '. A delete action still needs a real check: '
                  strong { 'scope the lookup' }
                  plain ' ('
                  code { 'current_user.todos.find' }
                  plain ') and '
                  code { 'authorize!' }
                  plain ' the record '
                  strong { 'before' }
                  plain ' '
                  code { 'destroy!' }
                  plain ' — the signed token proves identity, not permission.'
                end
                li do
                  strong { 'Pass the record to ' }
                  code { 'reply.remove' }
                  plain '. The remove target is the row component'
                  plain "'s "
                  code { 'dom_id' }
                  plain ' — so '
                  code { 'reply.remove(:notifications, todo)' }
                  plain ' hands it the record (fetched '
                  strong { 'before' }
                  plain ' '
                  code { 'destroy!' }
                  plain ', while it still answers '
                  code { 'dom_id' }
                  plain '). A raw integer id is not a dom_id and would target the wrong node; pass the record (or its '
                  code { 'dom_id' }
                  plain ' string) instead.'
                end
                li do
                  code { 'disable_with: "Adding…"' }
                  plain ' on the Add button disables it and swaps its label while the '
                  code { 'create!' }
                  plain ' is in flight — a collection add is the canonical pending-state case (see '
                  em { 'Instant feedback' }
                  plain ' below).'
                end
              end
            end
          end
        end

        def row_and_empty
          DocsUI::Section('The row and empty-state components') do
            DocsUI::Prose() do
              p do
                plain 'The row is a plain '
                code { 'Streamable' }
                plain ' keyed off the record, so its '
                code { '#id' }
                plain ' is a stable '
                code { 'dom_id' }
                plain ' — the append/remove target. Its dismiss button dispatches the '
                strong { "container's" }
                plain ' '
                code { 'dismiss' }
                plain ' action via the generic reactive controller it sits inside (it carries no token of its own):'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/notification_row.rb')
              class NotificationRow < ApplicationComponent
                include Phlex::Reactive::Component   # only to use `on` for the dismiss trigger

                def self.model_param_name = :todo
                def initialize(todo:) = @todo = todo
                def id = dom_id(@todo)

                def view_template
                  li(id:, class: "notification") do
                    span(class: "body") { @todo.title }
                    # optimistic hide: true hides the row the instant × is clicked,
                    # then reply.remove takes it out — no flash-back on success.
                    button(**mix(on(:dismiss, id: @todo.id,
                      confirm: "Dismiss?", optimistic: {hide: true, to: :root}))) { "×" }
                  end
                end
              end

              class NotificationsEmpty < ApplicationComponent
                include Phlex::Reactive::Streamable

                def id = "notifications-empty"
                def view_template = div(id:, class: "empty-state") { "No notifications" }
              end
            RUBY
          end
        end

        def what_each_reply_emits
          DocsUI::Section('What each reply emits') do
            DocsUI::Prose() do
              ul do
                li do
                  code { 'reply.append(name, model)' }
                  plain ' — append the row into the container · update the count · remove the empty-state when the '
                  plain 'list crosses 0→1.'
                end
                li do
                  code { 'reply.prepend(name, model)' }
                  plain ' — as '
                  code { 'append' }
                  plain ', row goes to the top.'
                end
                li do
                  code { 'reply.remove(name, model)' }
                  plain ' — remove the row by its '
                  code { 'dom_id' }
                  plain ' · update the count · append the empty-state back when the list crosses →0.'
                end
              end
              p do
                plain 'The empty-state is touched '
                strong { 'only at the boundary' }
                plain ' — adding to an already-populated list, or removing while rows remain, leaves it alone.'
              end
            end
          end
        end

        def add_to_top
          DocsUI::Section('Add to the top (prepend)') do
            DocsUI::Prose() do
              p do
                plain 'A notifications list usually shows the newest first. '
                code { 'reply.prepend' }
                plain ' is '
                code { 'append' }
                plain "'s twin — same row + count + empty-state contract, but the row lands at the "
                strong { 'top' }
                plain ' of the container instead of the bottom:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              def add(title:)
                todo = current_user.todos.create!(title:)
                reply.prepend(:notifications, todo)   # newest notification on top
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'Keep the first render in agreement: order the '
                code { 'view_template' }
                plain ' query the same way ('
                code { 'order(created_at: :desc)' }
                plain ' for newest-first) so a reload matches what '
                code { 'prepend' }
                plain ' streams in.'
              end
            end
          end
        end

        def instant_feedback
          DocsUI::Section('Instant feedback: pending Add, optimistic dismiss, failed create') do
            DocsUI::Prose() do
              p do
                plain "A collection's add and dismiss buttons are the canonical place for pending-state and "
                plain 'optimistic UX — the round trip includes a DB write, so the row should not appear frozen:'
              end
              ul do
                li do
                  code { 'disable_with: "Adding…"' }
                  plain ' on '
                  strong { 'Add' }
                  plain ' — disables the button and swaps its label from enqueue until the reply settles. A '
                  plain 'disabled button fires no further clicks, so a fast double-click enqueues exactly one '
                  code { 'create!' }
                  plain '. Style dimming/spinners off '
                  code { '[aria-busy="true"]' }
                  plain ' / '
                  code { 'busy_on(:add)' }
                  plain ' — both are on for free during the round trip.'
                end
                li do
                  code { 'optimistic: {hide: true, to: :root}' }
                  plain ' on '
                  strong { 'dismiss' }
                  plain ' — hides the row the instant × is clicked, before the round trip. Because '
                  code { 'reply.remove' }
                  plain ' does '
                  strong { 'not' }
                  plain ' re-render the row root, the hide is left standing on success (the row then removes) — '
                  plain 'no flash-back. A failed dismiss replays the inverse and the row reappears.'
                end
              end
              p do
                plain 'When the create can fail (a blank title, a validation), catch it and flash instead of letting '
                plain 'the 500 surface — a self-dismissing '
                code { 'reply.flash' }
                plain ' keeps the list intact:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              def add(title:)
                todo = current_user.todos.new(title:)
                if todo.save
                  reply.append(:notifications, todo)
                else
                  # No row, no count change — just a flash that clears itself after 4s.
                  reply.streams.flash(:error, todo.errors.full_messages.to_sentence, dismiss_after: 4000)
                end
              end
            RUBY
            DocsUI::Prose() do
              p do
                code { 'reply.streams' }
                plain ' (no arguments) emits the flash + the container'
                plain "'s token-only refresh and "
                strong { 'nothing else' }
                plain ' — the list is untouched, and the '
                code { 'title' }
                plain ' field the user is mid-typing in is never torn down. '
                code { 'dismiss_after:' }
                plain ' removes the flash after the timeout with no follow-up action.'
              end
            end
          end
        end

        def why_count_right
          DocsUI::Section('Why the count is always right') do
            DocsUI::Prose() do
              p do
                code { 'size:' }
                plain ' is '
                strong { 're-counted server-side after the mutation' }
                plain ', not incremented on a number the client holds. That is deliberate:'
              end
              ul do
                li do
                  strong { 'No off-by-one.' }
                  plain ' The badge reflects the database, not an optimistic guess.'
                end
                li do
                  strong { 'No state shipped to the client.' }
                  plain ' A client-held count would violate the signed-identity rule (the DOM never carries raw '
                  plain 'state) and would drift under concurrent changes from other tabs.'
                end
                li do
                  strong { 'First render and deltas agree.' }
                  plain ' Both read the same '
                  code { 'size:' }
                  plain ' source.'
                end
              end
              li do
                strong { 'Scope it to this list.' }
                plain ' '
                code { 'size:' }
                plain ' resolves in the container'
                plain "'s context, so it counts "
                strong { 'this' }
                plain ' list — '
                code { 'current_user.todos.size' }
                plain ', not a global '
                code { 'Todo.count' }
                plain '. A per-parent list scopes through its record ('
                code { '-> { @record.items.size }' }
                plain ') so two parents on one page each report their own size.'
              end
              p do
                code { 'count:' }
                plain ', '
                code { 'empty:' }
                plain ', and '
                code { 'size:' }
                plain ' are all optional — omit them and '
                code { 'reply.append' }
                plain ' emits just the row stream.'
              end
            end
          end
        end

        def repeated_add_remove
          DocsUI::Section("Repeated add/remove: the container's token rolls forward") do
            DocsUI::Prose() do
              p do
                code { 'reply.append' }
                plain ' / '
                code { 'reply.remove' }
                plain " don't re-render the whole container (that would clobber the streamed-in rows), so they ride "
                plain 'the same token-only refresh as '
                code { 'reply.streams' }
                plain ': each reply emits an inert '
                code { '<turbo-stream action="reactive:token">' }
                plain ' that rolls the '
                strong { "list root's" }
                plain ' signed token forward. That is the load-bearing part — the add/remove trigger lives on the '
                plain 'list root, so without the refresh the list would be '
                strong { 'add-once-only' }
                plain ' (correct on the first click, then every later dispatch rejected because the container'
                plain "'s token went stale, with no error). The helper bakes this in, so repeated adds and removes "
                plain 'just work.'
              end
              p do
                plain 'This holds even when the '
                strong { 'rows are themselves reactive' }
                plain ' (each row carries its own signed token) and they are appended directly '
                strong { 'into' }
                plain ' the container element (the container'
                plain "'s "
                code { '#id' }
                plain ' is the append target). A reactive child'
                plain "'s token, embedded in the appended content at the container's target, is "
                strong { 'not' }
                plain " the container's own refresh — the endpoint only counts a stream that re-renders the "
                plain "container's root ("
                code { 'replace' }
                plain '/'
                code { 'update' }
                plain '/'
                code { 'reactive:token' }
                plain '), so the container'
                plain "'s token still rolls forward and the list keeps working (#44). The "
                strong { 'client' }
                plain ' applies the same rule when it reads the next token out of the response: it takes the token '
                plain 'that re-renders '
                strong { 'its own' }
                plain ' element id (the trailing '
                code { 'reactive:token' }
                plain ' stream for the container), never the first token in the body — which, for a '
                plain 'prepended/appended reactive row, is the '
                strong { "row's" }
                plain " token, not the list's. Reading the first match made the list add-once-only "
                strong { 'in the browser' }
                plain ' even though the server response was correct (#46).'
              end
            end
          end
        end

        def cross_tab
          DocsUI::Section('Cross-tab: keep broadcasting the row') do
            DocsUI::Prose() do
              p do
                code { 'reactive_collection' }
                plain ' governs the '
                strong { "actor's" }
                plain ' HTTP reply. For a '
                strong { 'live' }
                plain ' list where other viewers see the row appear, broadcast the row as well, excluding the '
                plain 'actor (who already got the reply):'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              def add(title:)
                todo = current_user.todos.create!(title:)
                NotificationRow.broadcast_append_to(
                  current_user, :notifications,
                  target: "notifications", model: todo,
                  exclude: reactive_connection_id
                )
                reply.append(:notifications, todo)
              end
            RUBY
            DocsUI::Prose() do
              p do
                code { 'reactive_collection' }
                plain ' is the per-actor add/remove + count + empty-state wrapper; the broadcast is the cross-tab '
                plain 'fan-out. They compose — both target the same container id.'
              end
            end
          end
        end

        def related
          DocsUI::Section('Related') do
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Notifications / badges' }
                  plain ' — pure-broadcast badges (no client action), the natural complement when the server '
                  plain 'pushes a re-render.'
                end
                li do
                  strong { 'Live todo list' }
                  plain ' — the hand-rolled add/toggle/remove this helper distills.'
                end
              end
            end
          end
        end
      end
    end
  end
end
