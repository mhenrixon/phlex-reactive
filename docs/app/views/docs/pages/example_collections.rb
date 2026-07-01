# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleCollections < ::Docs::Page
        title 'Reactive collections'
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
          why_count_right
          repeated_add_remove
          cross_tab
          related
        end

        private

        def intro
          render ::Docs::Section.new('Example: reactive collections (add/remove rows + count + empty-state)') do
            render ::Docs::Prose.new do
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
          render ::Docs::Section.new('Declare the collection on the container') do
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              class NotificationsList < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component

                reactive_collection :notifications,
                  item: NotificationRow,         # the per-row Streamable component
                  container: "notifications",     # the DOM id rows live in
                  count: "notifications-count",   # optional companion id (the size badge)
                  empty: NotificationsEmpty,      # optional empty-state component
                  size: -> { Todo.count }         # resolves the live size (re-counted server-side)

                action :add, params: {title: :string}
                action :dismiss, params: {id: :integer}

                def id = "notifications-list"

                def add(title:)
                  todo = Todo.create!(title:)
                  reply.append(:notifications, todo)   # row + bump count + clear empty-state
                end

                def dismiss(id:)
                  Todo.find(id).destroy!
                  reply.remove(:notifications, id)     # row + bump count + restore empty-state at 0
                end

                def view_template
                  div(**reactive_root) do
                    span(id: "notifications-count") { Todo.count.to_s }

                    ul(id: "notifications") do
                      if Todo.exists?
                        Todo.order(:created_at, :id).each { |t| render NotificationRow.new(todo: t) }
                      else
                        render NotificationsEmpty.new
                      end
                    end

                    div do
                      input(name: "title", placeholder: "New notification…", autocomplete: "off")
                      button(**mix(on(:add))) { "Add" }
                    end
                  end
                end
              end
            RUBY
            render ::Docs::Prose.new do
              p do
                plain 'The same three things the helper streams in and out on each delta — the row, the count, the '
                plain 'empty-state — are what '
                code { 'view_template' }
                plain ' renders on first paint, so the initial server render and the reactive deltas cannot drift.'
              end
            end
          end
        end

        def row_and_empty
          render ::Docs::Section.new('The row and empty-state components') do
            render ::Docs::Prose.new do
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
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/notification_row.rb')
              class NotificationRow < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component   # only to use `on` for the dismiss trigger

                def self.model_param_name = :todo
                def initialize(todo:) = @todo = todo
                def id = dom_id(@todo)

                def view_template
                  li(id:, class: "notification") do
                    span(class: "body") { @todo.title }
                    button(**mix(on(:dismiss, id: @todo.id))) { "×" }
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
          render ::Docs::Section.new('What each reply emits') do
            render ::Docs::Prose.new do
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

        def why_count_right
          render ::Docs::Section.new('Why the count is always right') do
            render ::Docs::Prose.new do
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
          render ::Docs::Section.new("Repeated add/remove: the container's token rolls forward") do
            render ::Docs::Prose.new do
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
          render ::Docs::Section.new('Cross-tab: keep broadcasting the row') do
            render ::Docs::Prose.new do
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
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/notifications_list.rb')
              def add(title:)
                todo = Todo.create!(title:)
                NotificationRow.broadcast_append_to(
                  current_user, :notifications,
                  target: "notifications", model: todo,
                  exclude: reactive_connection_id
                )
                reply.append(:notifications, todo)
              end
            RUBY
            render ::Docs::Prose.new do
              p do
                code { 'reactive_collection' }
                plain ' is the per-actor add/remove + count + empty-state wrapper; the broadcast is the cross-tab '
                plain 'fan-out. They compose — both target the same container id.'
              end
            end
          end
        end

        def related
          render ::Docs::Section.new('Related') do
            render ::Docs::Prose.new do
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
