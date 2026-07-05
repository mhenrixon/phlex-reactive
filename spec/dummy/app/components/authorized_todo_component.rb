# frozen_string_literal: true

# verify_authorized fixture (issue #168). Record-backed so the request specs can
# assert a DB mutation ROLLS BACK when an action fails the guard. It defines its
# own `authorize!` (the interceptor wraps it, marking the tracking cell on a
# non-raising return — exactly how a real app's Pundit/CanCanCan helper behaves)
# and exercises every guard path across its actions:
#
#   rename           — calls authorize! (intercepted) → passes the guard
#   rename_marked    — calls mark_authorized! (manual) → passes the guard
#   rename_unguarded — authorizes NOTHING → the guard raises + rolls back
#   rename_skipped   — per-action skip_verify_authorized → bypasses the guard
#   rename_denied    — authorize! RAISES (registered) → 403, no mark, no mutation
class AuthorizedTodoComponent < ApplicationComponent
  include Phlex::Reactive::Component

  # Registered in config/initializers/phlex_reactive.rb so a raise maps to 403.
  class Denied < StandardError; end

  reactive_record :todo

  action :rename, params: { title: :string }
  action :rename_marked, params: { title: :string }
  action :rename_unguarded, params: { title: :string }
  action :rename_skipped, params: { title: :string }
  action :rename_denied, params: { title: :string }

  # Only this action is public-by-declaration; the rest must authorize.
  skip_verify_authorized :rename_skipped

  def initialize(todo:)
    @todo = todo
  end

  # The app-provided authorization helper the interceptor wraps. Returns truthy
  # on allow; raises Denied on deny (the deny path is exercised by rename_denied).
  # Named `authorize!` (bang, not `?`) to mirror the real Pundit/CanCanCan helper
  # the interceptor targets — the predicate-naming cop doesn't apply.
  def authorize!(allowed: true) # rubocop:disable Naming/PredicateMethod
    raise Denied, "not allowed" unless allowed

    true
  end

  def rename(title:)
    authorize!
    @todo.update!(title:)
  end

  def rename_marked(title:)
    # A bespoke check the interceptor can't see — assert it manually.
    mark_authorized!
    @todo.update!(title:)
  end

  # Mutates, then authorizes nothing — the guard must raise AND roll the update
  # back (fail-closed). The observable proof the transaction wrap works.
  def rename_unguarded(title:)
    @todo.update!(title:)
  end

  def rename_skipped(title:)
    @todo.update!(title:)
  end

  def rename_denied(title:)
    authorize!(allowed: false) # raises Denied → 403
    @todo.update!(title:)      # never reached
  end

  def view_template
    li(id:, **reactive_attrs) { @todo.title }
  end
end
