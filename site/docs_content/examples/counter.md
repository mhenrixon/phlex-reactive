---
layout: default
title: Counter
parent: Examples
nav_order: 1
---

# Example: counter (the smallest reactive component)

A record-less counter — the minimal thing that demonstrates client → server →
re-render. Use this to sanity-check your install.

```ruby
# app/components/counter.rb
class Counter < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count                       # signed state (no DB row)
  action :increment
  action :decrement
  action :set, params: { count: :integer }    # action with a typed param

  def initialize(count: 0) = @count = count
  def id = "counter"

  def increment = @count += 1
  def decrement = @count -= 1
  def set(count:) = @count = count

  def view_template
    div(**reactive_root(class: "counter")) do
      button(**on(:decrement)) { "−" }
      span(class: "value") { @count }
      button(**on(:increment)) { "+" }
      button(**on(:set, count: 0)) { "reset" }   # explicit param via on(...)
    end
  end
end
```

Render it anywhere:

```ruby
render Counter.new(count: 0)
```

## Notes

- **`reactive_state :count`** signs the count into the DOM token. On each action
  the server rebuilds `Counter.new(count: <verified>)`, runs the method, and
  re-renders. The new count is signed into the next token automatically.
- **`on(:set, count: 0)`** passes an explicit param. Explicit params win over
  any collected form fields.
- **Concurrency is handled.** Click `+` five times fast and you get `5` — the
  client serializes requests per component and threads the fresh token through,
  so rapid clicks don't clobber each other.
- This is record-less on purpose. For anything backed by data, prefer
  `reactive_record` so state lives in the DB (see
  [todo_list.md](todo_list.md)).
