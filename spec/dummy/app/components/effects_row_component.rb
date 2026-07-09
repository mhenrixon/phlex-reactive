# frozen_string_literal: true

# A state-backed row for the effects demo (issue #215). Declares its OWN
# enter/exit effects — the arriving append template root carries
# data-reactive-effect-enter (the client animates the inserted clone) and the
# in-DOM row carries data-reactive-effect-exit (a remove animates BEFORE the
# element leaves). dismiss_plain proves the per-call override: effect: false
# rides the stream as data-reactive-effect="off" and suppresses the declared
# exit for that one removal.
class EffectsRowComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :n
  reactive_effects enter: :slide, exit: :fade

  action :dismiss
  action :dismiss_plain

  def initialize(n: 1)
    @n = n
  end

  def id = "fx-row-#{@n}"

  def dismiss = reply.remove
  def dismiss_plain = reply.remove(effect: false)

  def view_template
    li(**reactive_root(data: { testid: id })) do
      span { "Row #{@n}" }
      button(**mix(on(:dismiss), data: { testid: "dismiss-#{@n}" })) { "×" }
      button(**mix(on(:dismiss_plain), data: { testid: "dismiss-plain-#{@n}" })) { "× (plain)" }
    end
  end
end
