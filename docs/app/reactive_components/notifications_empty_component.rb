# frozen_string_literal: true

# The empty-state shown when the notifications list is empty (issue #35). The
# reactive_collection helper removes it by its stable #id when the first row is
# added, and appends it back into the container when the last row is dismissed.
# A static view (Streamable only) — built argument-free.
class NotificationsEmptyComponent < Phlex::HTML
  include Phlex::Reactive::Streamable

  def id = 'notifications-empty'

  def view_template
    li(id:, class: 'py-3 text-sm opacity-60', data: { testid: 'empty-state' }) do
      'All caught up — no notifications.'
    end
  end
end
