# Example: notifications / live badges (pure broadcast, no client action)

Not every reactive component needs a client action. Sometimes the server just
needs to *push* a re-render — a notification badge that updates when a job
finishes, a live metric, a "new items available" pill. This uses only
`Phlex::Reactive::Streamable` (broadcasts), no `Component` mixin.

## A notification badge

```ruby
class NotificationsBadge < ApplicationComponent
  include Phlex::Reactive::Streamable

  def initialize(user:) = @user = user
  def id = dom_id(@user, :notifications_badge)
  def self.model_param_name = :user

  def view_template
    span(id:, class: "badge") do
      count = @user.notifications.unread.count
      plain(count.zero? ? "" : count.to_s)
    end
  end
end
```

Subscribe on the page:

```ruby
# in a layout or header component
turbo_stream_from current_user, :notifications
```

Push an update from anywhere — a model callback, a job, a service:

```ruby
class Notification < ApplicationRecord
  belongs_to :user
  after_create_commit do
    NotificationsBadge.broadcast_replace_to(user, :notifications, model: user)
  end
end
```

Now creating a notification re-renders the badge in every tab the user has open.
No client action, no Stimulus, no Action Cable.

## A "new items" pill driven by a background job

```ruby
class ImportJob < ApplicationJob
  def perform(import)
    import.run!
    # Re-render a status component for everyone watching this import.
    Imports::Status.broadcast_replace_to(import, model: import)
  end
end
```

```ruby
class Imports::Status < ApplicationComponent
  include Phlex::Reactive::Streamable

  def initialize(import:) = @import = import
  def id = dom_id(@import, :status)

  def view_template
    div(id:, class: "import-status #{@import.status}") do
      plain @import.status.titleize
      plain " — #{@import.processed_count}/#{@import.total_count}" if @import.running?
    end
  end
end
```

## When to use this vs a full reactive component

| Need | Use |
|---|---|
| Server pushes a re-render (job, callback, another user) | `Streamable` + `broadcast_*_to` |
| User clicks/types and the same component updates | add `Component` + `action` |
| Both | add `Component`; broadcast from inside the action |

Because both paths target the component by its `id`, you can start with a pure
broadcast badge and later add a `dismiss` action without changing the target or
the subscription.

## Transactional safety

If you broadcast from an `after_create_commit`/`after_update_commit` callback (or
from inside a transaction with pgbus), the broadcast only fires once the change
commits — a rolled-back notification never flashes a phantom badge. See
[docs/broadcasting.md](../broadcasting.md).
