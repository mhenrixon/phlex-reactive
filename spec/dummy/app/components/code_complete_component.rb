# frozen_string_literal: true

# Issue #226: the DECLARATIVE completion binding — reactive_on_complete with
# ZERO JavaScript (no reducer, no custom controller). The Ruby declaration
# compiles the length: condition through the ShowConditions language; the
# generic client evaluates it on every input and, on the rising edge, runs the
# declared op — here a dispatch the root's own on(:verify, event:
# "code:complete") binding turns into a signed action POST. Typing a 7th
# character makes the condition FALSE (len_eq 6) — re-arming the latch — so
# completion fires exactly at six characters, every time it becomes six.
class CodeCompleteComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :code
  action :verify, params: { code: :string }

  reactive_on_complete if: { code: { length: 6 } }, run: js.dispatch("code:complete")

  def initialize(code: "")
    @code = code
  end

  def id = "code-complete"

  def verify(code:)
    @code = code
  end

  def view_template
    div(**mix(reactive_root, on(:verify, event: "code:complete"))) do
      input(name: "code", value: @code, data: { testid: "code" })
      p(data: { testid: "status" }) { @code.empty? ? "waiting" : "verified:#{@code}" }
    end
  end
end
