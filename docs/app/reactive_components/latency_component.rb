# frozen_string_literal: true

# A tiny state-backed counter whose `bump` action is FAST server-side (no sleep)
# — exactly the localhost case where the ~5 ms round trip makes the busy window
# (aria-busy, disable_with:) flash by unobservably.
#
# It exists so the docs can DEMONSTRATE the loading/optimistic affordances: with
# the latency simulator toggled on (Views::Examples::LatencyToggle), every action
# is delayed client-side, so `disable_with:` text swaps and the `busy_on` spinner
# become visible without any server-side stall. Toggle the sim off and the same
# button is instant again — the affordance was always there, just too fast to see.
class LatencyComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :bump

  def initialize(count: 0)
    @count = count
  end

  def id = 'latency'

  # No sleep: the busy window is created purely by the client latency simulator,
  # not by a slow server action.
  def bump = @count += 1

  def view_template
    div(**reactive_root(class: 'flex items-center gap-3')) do
      # disable_with: swaps the label and disables the button while the action is
      # in flight — invisible on localhost until the simulator injects a delay.
      button(**mix(on(:bump, disable_with: 'Bumping…'),
                   class: 'btn btn-sm btn-primary', data: { testid: 'latency-bump' })) { 'Bump' }
      # A scoped busy indicator: data-reactive-busy toggles ONLY while bump is in
      # flight, revealed with pure CSS (loading loading-spinner), no Ruby.
      span(**mix(busy_on(:bump),
                 class: 'loading loading-spinner loading-sm', data: { testid: 'latency-spinner' }))
      span(class: 'text-2xl tabular-nums w-10 text-center',
           data: { testid: 'latency-count' }) { @count.to_s }
    end
  end
end
