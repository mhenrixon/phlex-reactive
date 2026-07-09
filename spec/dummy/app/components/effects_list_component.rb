# frozen_string_literal: true

# The effects demo container (issue #215). Declares update: :highlight so its
# own replace (ping) flashes the fresh root; add appends an EffectsRowComponent
# whose class-declared enter: :slide animates the arrival. add replies via
# reply.streams (no self re-render — a replace would clobber the existing
# rows), so the container's signed token rolls forward through the token-only
# refresh stream; the browser spec's second add is the add-once-only
# regression guard (cosmos#1939).
class EffectsListComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :next_n
  reactive_effects update: :highlight

  action :add
  action :ping

  def initialize(next_n: 2)
    @next_n = next_n
  end

  def id = "fx-demo"

  def add
    stream = EffectsRowComponent.append(target: "fx-rows", n: @next_n)
    @next_n += 1
    reply.streams(stream)
  end

  # Re-render self — the declared update: :highlight flashes the new root.
  # (A full replace resets the row list to the initial render; the spec pings
  # BEFORE adding rows, so nothing is lost.)
  def ping = reply.replace

  def view_template
    div(**reactive_root(data: { testid: "fx-demo" })) do
      button(**mix(on(:add), data: { testid: "fx-add" })) { "Add row" }
      button(**mix(on(:ping), data: { testid: "fx-ping" })) { "Ping" }
      ul(id: "fx-rows") do
        render EffectsRowComponent.new(n: 1)
      end
    end
  end
end
