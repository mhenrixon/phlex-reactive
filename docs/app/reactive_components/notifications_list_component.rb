# frozen_string_literal: true

# The reactive_collection demo container (issue #35). Declares the list contract
# ONCE — the row component, the container id, a companion count badge, an
# empty-state, and a size resolver — so add/dismiss append/remove a row + bump the
# count + toggle the empty-state with ONE reply call each, no per-action
# bookkeeping.
#
# State-backed (no single record), so it rebuilds from a signed token on each
# action. The size resolver reads the live DB count — always correct, never an
# off-by-one client increment. Dismiss also emits a self-dismissing flash
# (dismiss_after:) so the "Dismissed" toast clears itself after a beat.
class NotificationsListComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component
  include Phlex::Rails::Helpers::TurboStreamFrom

  reactive_collection :notifications,
                      item: NotificationRowComponent,
                      container: 'notifications',
                      count: 'notifications-count',
                      empty: NotificationsEmptyComponent,
                      size: -> { Notification.count }

  action :add, params: { title: :string }
  action :dismiss, params: { id: :integer }

  def id = 'notifications-list'

  # Append the new row + bump the count + clear the empty-state in ONE reply, and
  # broadcast the row to the OTHER tabs (append inserts a child, so exclude: the
  # actor or their own tab doubles it).
  def add(title:)
    title = title.to_s.strip
    return reply.replace if title.blank?

    notification = Notification.create!(title:)
    NotificationRowComponent.broadcast_to(*Notification.stream_key, append: notification,
                                                                    target: 'notifications',
                                                                    exclude: reactive_connection_id)
    reply.append(notification, to: :notifications)
  end

  # Remove the row + bump the count + restore the empty-state in ONE reply, plus a
  # self-dismissing flash. The broadcast_to(remove:) keeps other tabs in sync.
  def dismiss(id:)
    notification = Notification.find(id)
    notification.destroy!
    NotificationRowComponent.broadcast_to(*Notification.stream_key, remove: notification,
                                                                    exclude: reactive_connection_id)
    reply.remove(notification, from: :notifications).flash(:notice, 'Notification dismissed', dismiss_after: 3000)
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      turbo_stream_from(*Notification.stream_key) # cross-tab sync

      div(class: 'flex items-center gap-2') do
        span(class: 'font-medium') { 'Notifications' }
        span(id: 'notifications-count', class: 'badge badge-neutral badge-sm',
             data: { testid: 'count' }) { Notification.count.to_s }
      end

      ul(id: 'notifications', class: 'flex flex-col') do
        if Notification.exists?
          Notification.order(:created_at, :id).each { render NotificationRowComponent.new(notification: it) }
        else
          render NotificationsEmptyComponent.new
        end
      end

      div(class: 'flex gap-2') do
        input(name: 'title', placeholder: 'New notification…', autocomplete: 'off',
              class: 'input input-bordered input-sm flex-1', data: { testid: 'new-notification' })
        button(**mix(on(:add), class: 'btn btn-sm btn-primary', data: { testid: 'add' })) { 'Add' }
      end

      # The flash target the dismiss reply appends its self-dismissing toast into.
      div(id: 'flash', class: 'flex flex-col gap-1', data: { testid: 'flash' })
    end
  end
end
