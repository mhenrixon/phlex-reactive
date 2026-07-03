# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleTodoList < DocsUI::Page
        title 'Example: live todo list'
        eyebrow 'Examples'

        def lead
          'Per-row reactive components with add / toggle / rename / delete — optimistic delete, ' \
            'Enter-to-add, morph-preserved inline rename, and a broadcast on change so the list ' \
            'stays in sync across tabs and users. The canonical "list of records" pattern.'
        end

        def content
          live
          model
          row
          list
          collections
          broadcasting
          what_you_get
          keyed_lists
        end

        private

        def live
          DocsUI::Section('Try it') do
            md <<~MD
              This is a **real** reactive list rendered right here — not a
              screenshot. Add a row (Enter or the button), toggle it, rename it
              inline, or archive it. Each interaction POSTs to `/reactive/actions`,
              the server rebuilds the component from its signed token, runs the
              action, and re-renders in place — no Stimulus controller and no
              `.turbo_stream.erb` anywhere.
            MD
            render TodoListComponent.new
          end
        end

        def model
          DocsUI::Section('Model') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/models/todo.rb')
              class Todo < ApplicationRecord
                belongs_to :list
                validates :title, presence: true
                # Live cross-client sync over pgbus SSE — transactional, reconnect-safe.
                broadcasts_to ->(t) { [t.list, :todos] }, durable: true
              end
            RUBY
            md <<~MD
              `broadcasts_to` here only fires Turbo's default per-record
              broadcasts. We drive the precise UI updates from the reactive
              actions below (clearer for a component-rendered list), so you can
              also omit `broadcasts_to` and broadcast explicitly — shown inline.
            MD
          end
        end

        def row
          DocsUI::Section('One row (record-backed, all the actions)') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/todos/item.rb')
              class Todos::Item < ApplicationComponent
                include Phlex::Reactive::Component

                reactive_record :todo                    # identity AND the default #id: dom_id(@todo)
                action :toggle
                action :rename, params: { title: :string }
                action :cancel
                action :destroy

                def initialize(todo:) = @todo = todo
                # no `def id` needed: reactive_record :todo defaults it to dom_id(@todo)

                def toggle
                  authorize! @todo, :update?
                  @todo.update!(done: !@todo.done?)
                  broadcast
                end

                # Escape discards the in-progress edit — just re-render the row
                # from the persisted title (reply.morph keeps the caret, then the
                # server value overwrites the input's live text).
                def cancel = reply.morph

                # Morph in place so the focused rename <input> + caret survive the
                # re-render — the point of an inline editor (issue #28).
                def rename(title:)
                  authorize! @todo, :update?
                  @todo.update!(title:) if title.present?
                  broadcast
                  reply.morph
                end

                def destroy
                  authorize! @todo, :destroy?
                  list = @todo.list
                  @todo.destroy!
                  # Suppress the actor's own echo — they already handled it via reply.remove.
                  Todos::Item.broadcast_remove_to(list, :todos, model: @todo,
                                                  exclude: reactive_connection_id)
                  reply.remove                           # remove this tab's element in place
                end

                def view_template
                  li(**reactive_root(class: ("done" if @todo.done?))) do
                    # A checkbox that flips the INSTANT you click (optimistic: checked: :keep),
                    # before the round trip; the morph reconciles from server truth, a failure snaps it back.
                    input(type: "checkbox", checked: @todo.done?,
                      **mix(on(:toggle, event: "change", optimistic: { checked: :keep }), name: "done"))

                    # Enter saves the rename; Escape cancels (one action per element,
                    # so cancel lives on its own control). event: is Stimulus's native
                    # keyboard filter — the action fires only on that key, no custom JS.
                    reactive_input(:title, value: @todo.title, **on(:rename, event: "keydown.enter"))
                    button(**on(:cancel, event: "keydown.esc")) { "esc" }

                    # Instant delete: hide the row NOW, remove it on the reply.
                    button(**on(:destroy, confirm: "Delete?", disable_with: "…",
                                optimistic: { hide: true, to: :root })) { "✕" }
                  end
                end

                private

                # Re-render this row into every OTHER subscribed tab — exclude the
                # actor, whose own reply.morph / self-replace already updated them.
                def broadcast
                  Todos::Item.broadcast_replace_to(@todo.list, :todos, model: @todo,
                                                   exclude: reactive_connection_id)
                end
              end
            RUBY
            md <<~MD
              **`reactive_input(:title, …)`** drops the magic `name:` — it emits
              `<input name="title" …>` bound to the `rename` action's `title`
              param, so the field's value always travels with the action.

              **`optimistic: { checked: :keep }`** flips the checkbox client-side
              the instant you click — without it the reactive controller's
              `preventDefault` would leave the box unflipped until the morph
              arrives. `optimistic: { hide: true, to: :root }` on delete hides the
              row immediately; `reply.remove` then removes it, so it never flashes
              back. Hints are cosmetic and always-reversible — a failed round trip
              replays the inverse.

              **`disable_with: "…"`** disables the delete button while the action
              is in flight, so a rapid double-click fires the destroy exactly once.

              **`reply.morph`** (rename) re-renders via Idiomorph, preserving the
              focused input + caret — a plain `replace` would tear the field out
              from under the typist. **`reply.remove`** (destroy) drops the actor's
              own row with no doomed self re-render.
            MD
          end
        end

        def list
          DocsUI::Section('The list + composer') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/todos/list.rb')
              class Todos::List < ApplicationComponent
                include Phlex::Reactive::Component

                reactive_record :list
                action :add, params: { title: :string }

                def initialize(list:) = @list = list
                def id = dom_id(@list, :todos_panel)

                def add(title:)
                  authorize! @list, :update?
                  title = title.to_s.strip
                  return if title.blank?

                  todo = @list.todos.create!(title:)
                  # Append the new row into every OTHER subscribed tab. An append INSERTS
                  # a child (not id-deduped like a replace), so without exclude: the actor
                  # would get the row a second time on top of their own HTTP reply.
                  Todos::Item.broadcast_append_to(@list, :todos, target: dom_id(@list, :todos),
                                                  model: todo, exclude: reactive_connection_id)
                end

                def view_template
                  div(**reactive_root) do
                    turbo_stream_from @list, :todos                       # subscribe to live updates

                    ul(id: dom_id(@list, :todos)) do
                      @list.todos.order(:created_at).each { |t| render Todos::Item.new(todo: t) }
                    end

                    div do
                      # Enter in the field adds the todo — the same :add action the
                      # button fires on click. event: "keydown.enter" is Stimulus's
                      # native keyboard filter, so only Enter dispatches.
                      reactive_input(:title, placeholder: "New todo…", autocomplete: "off",
                        **on(:add, event: "keydown.enter"))
                      button(**on(:add, disable_with: "Adding…")) { "Add" }

                      # Client-only reset: clear the composer with ZERO round trip —
                      # no token, no POST, ever. Pure UX polish on its own trigger.
                      button(**on_client(:click, js.set_attr("[name=title]", "value", ""))) { "Clear" }
                    end
                  end
                end
              end
            RUBY
            md <<~MD
              **`broadcast_append_to(..., exclude: reactive_connection_id)`** is
              the load-bearing detail for a list. An `append` *inserts* a child —
              it is not id-deduped the way a `replace`/`morph` of an existing
              element is. Without `exclude:`, the actor's own subscribed tab would
              receive the broadcast and append the new row a **second** time, on
              top of the copy the action reply already rendered. (Toggle/rename use
              `broadcast_replace_to`, which idiomorph *does* dedupe by dom id — so
              the actor there is silently fine — but `exclude:` is still the
              correct, consistent pattern.)

              **`disable_with: "Adding…"`** stops a rapid double-click on **Add**
              from creating two todos; the button re-enables when the round trip
              settles. **`on_client(:click, js.set_attr(...))`** on the Clear
              button empties the field client-side with no token, no POST — a
              zero-round-trip DOM op the one generic controller applies locally.
            MD
          end
        end

        def collections
          DocsUI::Section('One-call add/remove: reactive_collection') do
            md <<~MD
              Hand-deriving the container id, the count badge, and the empty-state
              in every action gets repetitive. `reactive_collection` declares the
              list contract **once**; an action then appends or removes a row with
              a single `reply.append` / `reply.remove` that emits the row stream,
              the count companion, and the empty-state toggle as ONE reply.
            MD
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/todos/list.rb')
              class Todos::List < ApplicationComponent
                include Phlex::Reactive::Component

                reactive_record :list
                action :add, params: { title: :string }
                action :remove_todo, params: { id: :integer }

                # Declare the row list once: the row component, the container id
                # (a plain DOM id string), an optional count badge id, an optional
                # empty-state component, and the live size resolver (a proc,
                # instance_exec'd against the component).
                reactive_collection :todos,
                  item:      Todos::Item,
                  container: "todos",
                  count:     "todos-count",
                  empty:     Todos::Empty,
                  size:      -> { @list.todos.size }

                def initialize(list:) = @list = list
                def id = dom_id(@list, :todos_panel)

                def add(title:)
                  authorize! @list, :update?
                  title = title.to_s.strip
                  return if title.blank?

                  todo = @list.todos.create!(title:)
                  reply.append(:todos, todo)   # row + count + clears the empty-state, in one reply
                end

                def remove_todo(id:)
                  authorize! @list, :update?
                  @list.todos.find(id).destroy!
                  reply.remove(:todos, id)     # row remove + count + restores the empty-state
                end
              end
            RUBY
            md <<~MD
              `count:` and `empty:` are optional — a list with just rows omits them
              and those streams simply aren't emitted. The row component
              (`Todos::Item`) still owns its own toggle/rename/destroy actions; the
              collection is only about the container-level add/remove reply.
            MD
          end
        end

        def broadcasting
          DocsUI::Section('Broadcasting: suppress the actor echo') do
            md <<~MD
              Every mutating action above ends the same way: update the record,
              **broadcast to the other tabs, and reconcile the actor via the HTTP
              reply.** The one rule that keeps it correct is
              `exclude: reactive_connection_id` on the broadcast:

              - **`add` → `broadcast_append_to`** — an append inserts a child, so
                the actor MUST be excluded or the row double-applies (append is not
                id-deduped).
              - **`toggle` / `rename` → `broadcast_replace_to`** — a replace/morph
                is keyed by dom id, so idiomorph dedupes it for the actor even
                without `exclude:`. Passing `exclude:` anyway keeps every action on
                one consistent pattern and avoids a redundant echo.
              - **`destroy` → `broadcast_remove_to`** — remove is idempotent, so a
                double remove is invisible; `exclude:` still spares the actor a
                redundant echo they already handled via `reply.remove`.
            MD
            DocsUI::Callout(:tip) do
              md <<~MD
                Treat `exclude: reactive_connection_id` as the default on **every**
                broadcast that pairs with an actor reply. It's mandatory for
                `append`/`prepend` and harmless-but-consistent for
                `replace`/`morph`/`remove`. See
                [Broadcasting & live updates](/docs/broadcasting).
              MD
            end
          end
        end

        def what_you_get
          DocsUI::Section('What you get') do
            md <<~MD
              - Toggle, rename, add, delete — all without a Stimulus controller or a
                `.turbo_stream.erb`.
              - **Optimistic delete + instant toggle** via
                `optimistic: { hide: true }` / `optimistic: { checked: :keep }` — the
                UI reacts in the same gesture, the morph reconciles from server truth,
                and a failure snaps it back.
              - **Enter-to-add and Enter-to-save** via `on(:add, event:
                "keydown.enter")`, **Escape-to-cancel** via `event: "keydown.esc"` —
                Stimulus's native keyboard filter, no custom JavaScript.
              - **No double-submit:** `disable_with:` disables the Add / delete
                buttons while their action is in flight.
              - **Focus-preserving inline rename** via `reply.morph` (Idiomorph keeps
                the caret in the field), and a client-cleared composer via
                `on_client` + `js` — zero round trip.
              - Every change broadcasts the affected **row** (not the whole list) over
                pgbus SSE with `exclude: reactive_connection_id`, so other tabs/users
                update with a minimal payload and the actor never doubles.
              - `dom_id(@todo)` is the single source of truth for the row's identity:
                the morph target for actions AND broadcasts.
            MD
          end
        end

        def keyed_lists
          DocsUI::Section('Keyed lists & morphing') do
            md <<~MD
              Give each row a stable `id` (here `dom_id(@todo)`) so idiomorph can
              match rows across renders — that's what lets `reply.morph` preserve
              focus in the rename input and avoids re-creating unchanged rows.
              Turbo 8 morph keeps the focused field's in-progress value while
              writing the fresh server value as the new default.
            MD
            DocsUI::Callout(:warning, title: 'Don’t render list items without a stable id') do
              md <<~MD
                Without a stable per-row id, idiomorph can't key the rows: focus is
                lost in the rename input and unchanged rows are needlessly
                re-created. `reply.morph` only preserves the caret when the row it
                morphs has a stable id to match against.
              MD
            end
          end
        end
      end
    end
  end
end
