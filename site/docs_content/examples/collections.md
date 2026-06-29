---
layout: default
title: Reactive collections
parent: Examples
nav_order: 6
---

# Example: reactive collections (add/remove rows + count + empty-state)

An add/remove-row list — line items, attachments, tags, comments, a
notifications list — is one of the most common reactive surfaces. Each one
re-implements the same orchestration by hand in every action: append the new row
to the right container, remove it on delete, keep a **count badge** in sync, and
swap an **empty-state** in and out as the list crosses 0↔1. Each is easy to get
subtly wrong (off-by-one badge, empty-state not toggled, container id drift
between the static render and the action), and it's duplicated per list.

`reactive_collection` declares that contract **once** on the container, so each
action is a single call.

## Declare the collection on the container

```ruby
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
```

The same three things the helper streams in and out on each delta — the row, the
count, the empty-state — are what `view_template` renders on first paint, so the
initial server render and the reactive deltas can't drift.

## The row and empty-state components

The row is a plain `Streamable` keyed off the record, so its `#id` is a stable
`dom_id` — the append/remove target. Its dismiss button dispatches the
*container's* `dismiss` action via the generic reactive controller it sits inside
(it carries no token of its own):

```ruby
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
```

## What each reply emits

| Builder | Streams (one `Response`) |
|---|---|
| `reply.append(name, model)` | append the row into the container · update the count · remove the empty-state when the list crosses 0→1 |
| `reply.prepend(name, model)` | as `append`, row goes to the top |
| `reply.remove(name, model)` | remove the row by its `dom_id` · update the count · append the empty-state back when the list crosses →0 |

The empty-state is touched **only at the boundary** — adding to an already-populated
list, or removing while rows remain, leaves it alone.

## Why the count is always right

`size:` is **re-counted server-side after the mutation**, not incremented on a
number the client holds. That's deliberate:

- **No off-by-one.** The badge reflects the database, not an optimistic guess.
- **No state shipped to the client.** A client-held count would violate the
  signed-identity rule (the DOM never carries raw state) and would drift under
  concurrent changes from other tabs.
- **First render and deltas agree.** Both read the same `size:` source.

`count:`, `empty:`, and `size:` are all optional — omit them and `reply.append`
emits just the row stream.

## Repeated add/remove: the container's token rolls forward

`reply.append` / `reply.remove` don't re-render the whole container (that would
clobber the streamed-in rows), so they ride the same token-only refresh as
[`reply.streams`](../../#reply--controlling-the-actions-reply): each reply emits
an inert `<turbo-stream action="reactive:token">` that rolls the **list root's**
signed token forward. That's the load-bearing part — the add/remove trigger lives
on the list root, so without the refresh the list would be *add-once-only*
(correct on the first click, then every later dispatch rejected because the
container's token went stale, with no error). The helper bakes this in, so
repeated adds and removes just work.

This holds even when the **rows are themselves reactive** (each row carries its
own signed token) and they're appended directly *into* the container element (the
container's `#id` is the append target). A reactive child's token, embedded in the
appended content at the container's target, is **not** the container's own
refresh — the endpoint only counts a stream that re-renders the container's root
(`replace`/`update`/`reactive:token`), so the container's token still rolls forward
and the list keeps working (#44). The **client** applies the same rule when it
reads the next token out of the response: it takes the token that re-renders *its
own* element id (the trailing `reactive:token` stream for the container), never the
first token in the body — which, for a prepended/appended reactive row, is the
**row's** token, not the list's. Reading the first match made the list add-once-only
*in the browser* even though the server response was correct (#46).

## Cross-tab: keep broadcasting the row

`reactive_collection` governs the **actor's** HTTP reply. For a *live* list where
other viewers see the row appear, broadcast the row as well, excluding the actor
(who already got the reply):

```ruby
def add(title:)
  todo = Todo.create!(title:)
  NotificationRow.broadcast_append_to(
    current_user, :notifications,
    target: "notifications", model: todo,
    exclude: reactive_connection_id
  )
  reply.append(:notifications, todo)
end
```

`reactive_collection` is the per-actor add/remove + count + empty-state wrapper;
the broadcast is the cross-tab fan-out. They compose — both target the same
container id. See [docs/broadcasting.md](../broadcasting.md).

## Related

- [Notifications / badges](notifications) — pure-broadcast badges (no client
  action), the natural complement when the server pushes a re-render.
- [Live todo list](todo_list) — the hand-rolled add/toggle/remove this helper
  distills.
