# Example: live todo list

Per-row reactive components with add / toggle / rename / delete, broadcasting on
change so the list stays in sync across tabs and users. This is the canonical
"list of records" pattern.

## Model

```ruby
class Todo < ApplicationRecord
  belongs_to :list
  # Live cross-client sync over pgbus SSE — transactional, reconnect-safe.
  broadcasts_to ->(t) { [t.list, :todos] }, durable: true
end
```

`broadcasts_to` here only fires Turbo's default per-record broadcasts. We drive
the precise UI updates from the reactive actions below, which is clearer for a
component-rendered list — so you can also omit `broadcasts_to` and broadcast
explicitly (shown inline).

## One row (record-backed, all the actions)

```ruby
class Todos::Item < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: { title: :string }
  action :destroy

  def initialize(todo:) = @todo = todo
  def id = dom_id(@todo)

  def toggle
    authorize! @todo, :update?
    @todo.toggle!(:done)
    broadcast
  end

  def rename(title:)
    authorize! @todo, :update?
    @todo.update!(title: title)
    broadcast
  end

  def destroy
    authorize! @todo, :destroy?
    list = @todo.list
    @todo.destroy!
    # Remove from every other tab; this tab's own response also removes it.
    Todos::Item.broadcast_remove_to(list, :todos, model: @todo)
  end

  def view_template
    li(id:, **reactive_attrs, class: ("done" if @todo.done?)) do
      button(**on(:toggle)) { @todo.done? ? "✓" : "○" }
      input(name: "title", value: @todo.title, **on(:rename, event: "change"))
      button(**on(:destroy)) { "✕" }
    end
  end

  private

  # Re-render this row into every other subscribed tab.
  def broadcast
    Todos::Item.broadcast_replace_to(@todo.list, :todos, model: @todo)
  end
end
```

Note `destroy` returns a *replace* of a now-deleted row in the action response.
Render `to_stream_replace` of a tombstone, or override the endpoint to send a
`remove` — the simplest path is to also handle removal client-side via the
broadcast and let the action response be a no-op replace of an empty row. For
clarity most apps make `destroy` an action whose response removes the element;
see [docs/broadcasting.md](../broadcasting.md#removing-the-actors-own-element).

## The list + composer

```ruby
class Todos::List < ApplicationComponent
  include Phlex::Reactive::Streamable
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
    Todos::Item.broadcast_append_to(@list, :todos, target: dom_id(@list, :todos), model: todo)
  end

  def view_template
    div(id:, **reactive_attrs) do
      turbo_stream_from @list, :todos                       # subscribe to live updates

      ul(id: dom_id(@list, :todos)) do
        @list.todos.order(:created_at).each { |t| render Todos::Item.new(todo: t) }
      end

      div do
        input(name: "title", placeholder: "New todo…", autocomplete: "off")
        button(**on(:add)) { "Add" }
      end
    end
  end
end
```

## What you get

- Toggle, rename (on `change`), add, delete — all without a Stimulus controller
  or a `.turbo_stream.erb`.
- Every change broadcasts the affected **row** (not the whole list) over pgbus
  SSE, so other tabs/users update with a minimal payload.
- `dom_id(@todo)` is the single source of truth for the row's identity: the
  morph target for actions AND broadcasts.

## Keyed lists & morphing

Give each row a stable `id` (here `dom_id(@todo)`) so idiomorph can match rows
across renders — that preserves focus in the rename input and avoids
re-creating unchanged rows. Don't render list items without a stable id.
