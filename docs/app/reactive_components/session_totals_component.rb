# frozen_string_literal: true

# The deliberately slow rollup behind the defer example (issue #165) — the
# "session totals" from the reps-logger story that motivated reply.defer. The
# template sleeps ~400 ms to simulate a genuinely expensive cross-aggregate
# rollup, so the pending window is visible even on a localhost round trip.
#
# reactive_lazy: the FIRST (page-embedded) render ships a placeholder shell
# instead of paying the 400 ms on the docs page render; the client fetches the
# real totals on connect through the same defer machinery reply.defer uses.
# Every reactive-machinery render (a reply, the defer endpoint) is REAL, so an
# action on this component never costs a double fetch.
class SessionTotalsComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :sets

  reactive_lazy

  def initialize(sets: 0)
    @sets = sets
  end

  def id = 'session-totals'

  # Rendered inside the pending shell by `placeholder: true` AND by the lazy
  # mount's shell. A plain String is escaped as text (data, not markup);
  # return a Phlex component instance or an html_safe String for real
  # skeleton markup.
  def deferred_placeholder = 'Crunching totals…'

  def view_template
    sleep(0.4) # the deliberately expensive rollup — the reason to defer it
    div(**reactive_root(class: 'flex items-center gap-4 rounded-box bg-base-200 px-4 py-3')) do
      stat('Sets', @sets.to_s, testid: 'totals-sets')
      stat('Volume', "#{@sets * 240} kg", testid: 'totals-volume')
      span(class: 'text-xs opacity-60', data: { testid: 'totals-computed' }) do
        plain "computed at #{Time.current.strftime('%H:%M:%S.%L')}"
      end
    end
  end

  private

  def stat(label, value, testid:)
    span(class: 'flex flex-col') do
      span(class: 'text-xs uppercase opacity-60') { label }
      span(class: 'text-lg font-semibold tabular-nums', data: { testid: }) { value }
    end
  end
end
