# frozen_string_literal: true

# Issue #226: the MULTI-BOX code entry — six single-character inputs behind one
# "split_code" reducer (see public/vendor/split_code_reducer.js). The reducer
# joins the boxes on every input, redistributes one digit per box (a paste into
# any box fans out across all six), mirrors the joined code into the hidden
# `code` field, advances focus to the first empty box via a per-digit $ops
# focus (the content-keyed latch fires each DIFFERENT target), and submits on
# completion — the same on(:verify, event: "submit") interception as the
# single-input VerificationCodeComponent.
class SplitCodeComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  BOXES = %i[d1 d2 d3 d4 d5 d6].freeze

  reactive_state :code
  action :verify, params: { code: :string }

  # No maxlength on the boxes: it would truncate a paste before the reducer
  # could redistribute it. The reducer caps at one digit per box instead.
  reactive_compute :split_code,
    inputs: BOXES.to_h { [it, :string] },
    outputs: BOXES + [:code]

  def initialize(code: "")
    @code = code
  end

  def id = "split-code"

  def verify(code:)
    @code = code
  end

  def view_template
    form(action: "/nav_probe", method: "post",
      **mix(reactive_root(compute: :split_code), on(:verify, event: "submit"))) do
      BOXES.each_with_index do |name, i|
        input(name:, value: @code[i].to_s, inputmode: "numeric", size: 2,
          data: { testid: name })
      end
      input(type: "hidden", name: "code", value: @code)
      button(type: "submit", data: { testid: "verify" }) { "Verify" }
      p(data: { testid: "status" }) { @code.empty? ? "waiting" : "verified:#{@code}" }
    end
  end
end
