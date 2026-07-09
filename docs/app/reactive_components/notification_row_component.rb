# frozen_string_literal: true

# A single notification row in the reactive_collection demo (issue #35). Keyed
# off a Notification record so its #id is a stable dom_id — the append/remove
# target for the collection helper.
#
# The row carries NO token of its own (no reactive_attrs): its dismiss button
# dispatches the CONTAINER's `dismiss` action via the generic reactive controller
# it sits inside, so the client sends the container's token. It includes Component
# only to build that dispatch — the same attrs whether the row is rendered on
# first paint or streamed in by reply.append.
class NotificationRowComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Effects (issue #215): an arriving notification slides in — for the actor's
  # reply.append AND the cross-tab broadcast append alike. Dismiss stays
  # instant for the actor (the optimistic hide already removed it from view);
  # peers see the broadcast remove fade the row out.
  reactive_effects enter: :slide, exit: :fade

  def self.model_param_name = :notification

  def initialize(notification:)
    @notification = notification
  end

  def id = dom_id(@notification)

  def view_template
    li(id:, class: 'flex items-center justify-between gap-3 border-b border-base-200 py-2',
       data: { testid: 'notification' }) do
      span(class: 'text-sm') { @notification.title }
      # optimistic: { hide: true } hides the row the instant you click, before the
      # round trip; reply.remove then drops it so it never flashes back. dismiss is
      # the CONTAINER's action (the row has no token of its own) — so `to:` targets
      # THIS row by its own id, NOT :root (which would be the whole list). Keyed by id.
      button(**mix(on(:dismiss, id: @notification.id, optimistic: { hide: true, to: "##{id}" }),
                   class: 'btn btn-xs btn-ghost', data: { testid: 'dismiss' })) { '×' }
    end
  end
end
