# frozen_string_literal: true

# The empty-state shown when the notifications list is empty (issue #35). The
# reactive_collection helper removes it by its stable #id when the first row is
# added, and appends it back into the container when the last row is dismissed.
# It is a static view — built argument-free.
class NotificationsEmptyComponent < ApplicationComponent
  include Phlex::Reactive::Streamable

  def id = "notifications-empty"

  def view_template
    div(id:, class: "empty-state", data: { testid: "empty-state" }) { "No notifications" }
  end
end
