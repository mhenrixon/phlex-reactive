# frozen_string_literal: true

# A live notification bell (issue #35 broadcasts). It subscribes to a shared
# stream and shows an unread count. "Simulate a background event" stands in for a
# job finishing: it bumps the count and BROADCASTS the re-rendered bell to every
# subscribed tab (so a second window updates with no action of its own), then
# fires a `broadcast_js_to` nudge — a pure client-side pulse animation applied on
# the OTHER tabs with no re-render at all.
#
# This is the "the server just pushes" shape: the count update rides a normal
# broadcast_replace, and the attention-grab (the pulse) rides broadcast_js_to,
# which ships a whitelisted DOM op — not HTML — to every subscriber.
class NotificationBellComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component
  include Phlex::Rails::Helpers::TurboStreamFrom

  STREAM = %w[notification-bell all].freeze

  reactive_state :unread
  action :simulate_event

  def initialize(unread: 0)
    @unread = unread.to_i
  end

  def id = 'notification-bell'

  # Bump the count, then push the update to EVERY subscribed tab (the actor
  # included — a replace is id-deduped, so the actor's own HTTP reply and the
  # broadcast reconcile to the same DOM). broadcast_replace_to rebuilds the bell
  # from the given state (unread:). The broadcast_js_to nudge pulses the bell on
  # the OTHER tabs only (exclude: the actor, who already saw the bump).
  def simulate_event
    @unread += 1
    NotificationBellComponent.broadcast_replace_to(*STREAM, unread: @unread)
    NotificationBellComponent.broadcast_js_to(
      *STREAM,
      js.add_class('#bell-icon', 'animate-bounce'),
      exclude: reactive_connection_id
    )
  end

  def view_template
    div(**reactive_root(class: 'flex items-center gap-3')) do
      turbo_stream_from(*STREAM) # subscribe to the pushed updates

      div(id: 'bell-icon', class: 'relative inline-flex') do
        span(class: 'text-2xl') { '🔔' }
        if @unread.positive?
          span(class: 'badge badge-error badge-sm absolute -right-2 -top-2',
               data: { testid: 'bell-count' }) { @unread.to_s }
        end
      end

      button(**mix(on(:simulate_event),
                   class: 'btn btn-sm btn-primary', data: { testid: 'simulate' })) do
        'Simulate a background event'
      end
    end
  end
end
