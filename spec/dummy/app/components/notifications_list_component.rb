# frozen_string_literal: true

# The reactive_collection demo container (issue #35). Declares the list contract
# ONCE — the row component, the container id, a companion count badge, an
# empty-state, and a size resolver — so the add/dismiss actions append/remove a
# row + bump the count + toggle the empty-state with ONE reply call each, no
# per-action bookkeeping.
#
# State-backed (no single record), so it rebuilds from a signed token on each
# action. The size resolver reads the live count from the DB — always correct,
# never an off-by-one client increment.
class NotificationsListComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_collection :notifications,
    item: NotificationRowComponent,
    container: "notifications",
    count: "notifications-count",
    empty: NotificationsEmptyComponent,
    size: -> { Todo.count }

  action :add, params: { title: :string }
  action :dismiss, params: { id: :integer }

  def id = "notifications-list"

  def add(title:)
    title = title.to_s.strip
    return reply.replace if title.blank?

    todo = Todo.create!(title:)
    reply.append(:notifications, todo)
  end

  def dismiss(id:)
    todo = Todo.find(id)
    todo.destroy!
    reply.remove(:notifications, todo)
  end

  def view_template
    div(id:, **reactive_attrs) do
      span(id: "notifications-count", data: { testid: "count" }) { Todo.count.to_s }

      ul(id: "notifications") do
        if Todo.exists?
          Todo.order(:created_at, :id).each { render NotificationRowComponent.new(it:) }
        else
          render NotificationsEmptyComponent.new
        end
      end

      div do
        input(name: "title", placeholder: "New notification…", autocomplete: "off", data: { testid: "new-notification" })
        button(**mix(on(:add), data: { testid: "add" })) { "Add" }
      end
    end
  end
end
