---
title: Broadcasting
nav_order: 5
---

# Broadcasting & live updates

Reactive *actions* update the acting user's screen. **Broadcasts** update
everyone else's. Both target the component by its `id`, so they compose.

## The pattern

```ruby
# Subscribe (in the view that should receive updates):
turbo_stream_from @list, :todos

# Broadcast (from a model callback, job, service, or a reactive action):
Todos::Item.broadcast_replace_to(@list, :todos, model: @todo)
```

The subscriber and broadcaster must agree on the **same stream key**. Pass the
same `*streamables` to both `turbo_stream_from` and `broadcast_*_to`.

## Stream keys: pass raw parts, not a built key

`broadcast_*_to(*streamables, ...)` builds the stream key itself. **Pass raw
parts** (a record and/or symbols), not an already-built key string:

```ruby
# GOOD — raw parts
Chat::Message.broadcast_append_to("chat", room, target: "...", model: msg)
turbo_stream_from "chat", room

# BAD — double-keying ("chat:lobby" then re-keyed) trips the separator guard
key = ChatMessage.stream_key(room)             # => "chat:lobby"
Chat::Message.broadcast_append_to(key, ...)    # ArgumentError under pgbus
```

If you have a helper that returns a built key for the subscriber, pass the *same
built string* to `turbo_stream_from` only — but give `broadcast_*_to` the raw
parts. The simplest rule: **use the same raw `*streamables` on both sides.**

## The broadcast methods

| Method | Effect |
|---|---|
| `.broadcast_replace_to(*streamables, model:)` | Replace the element with id `component.id` |
| `.broadcast_update_to(*streamables, model:)` | Replace its *inner* HTML |
| `.broadcast_append_to(*streamables, target:, model:)` | Append into container `target` |
| `.broadcast_prepend_to(*streamables, target:, model:)` | Prepend into `target` |
| `.broadcast_remove_to(*streamables, model:)` | Remove the element with id `component.id` |

## Broadcasting from inside a reactive action

The acting user gets the action's HTTP response (a replace of the component).
*Everyone else* gets the broadcast. Idiomorph dedupes by DOM id, so the actor
doesn't double-apply an append they triggered:

```ruby
def add(title:)
  authorize! @list, :update?
  todo = @list.todos.create!(title:)
  Todos::Item.broadcast_append_to(@list, :todos, target: dom_id(@list, :todos), model: todo)
end
```

## Transactional broadcasts (with pgbus)

The action endpoint runs your action inside a transaction. With pgbus,
broadcasts defer to `after_commit`, so:

- A broadcast inside a transaction that **rolls back never fires** — *and* the DB
  change is undone. No phantom UI update for a change that didn't happen.
- This is the correctness property neither Action Cable nor Livewire give you
  cleanly.

```ruby
ActiveRecord::Base.transaction do
  @order.update!(status: "shipped")
  Orders::Card.broadcast_replace_to(@order.account, model: @order)  # deferred
  ChargeService.capture!(@order)   # if this raises → no broadcast, no status change
end
```

## Removing the actor's own element

`destroy`-style actions are the one case where "replace the component by its id"
doesn't fit (the element should vanish, not be replaced). Options:

1. **Broadcast a remove and make the action response a remove too.** Override the
   endpoint, or have the action render `to_stream_remove` (add a small helper),
   so the actor's element is removed and everyone else's via broadcast.
2. **Replace with an empty/tombstone state** if you want an "undo" affordance.

Most apps add a tiny `to_stream_remove` to `Streamable` for this:

```ruby
def to_stream_remove
  self.class.turbo_stream_builder.remove(id)
end
```

and return it from a destroy action via a custom endpoint hook. See
[architecture.md](architecture.md) for the dispatch path.

## Presence (who's here / typing)

pgbus ships presence tracking. Join on render, leave on disconnect, broadcast the
change:

```ruby
Pgbus.stream(@room).presence.join(member_id: current_user.id, metadata: { name: current_user.name }) do |member|
  Chat::PresencePill.replace(member: member)  # rendered HTML to broadcast
end

Pgbus.stream(@room).presence.members   # current list
Pgbus.stream(@room).presence.count     # fast count for a "N online" badge
```

See [transport-pgbus.md](transport-pgbus.md).
