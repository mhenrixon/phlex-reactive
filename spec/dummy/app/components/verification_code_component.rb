# frozen_string_literal: true

# Issue #226: the $ops flagship — a one-time-code field that is a
# reactive_field + a reducer and NOTHING else. The "otp" reducer (see
# public/vendor/otp_reducer.js) normalizes on every input (strip non-digits,
# cap at 6) and, once complete, returns `$ops: ops.submit()`. The component
# root IS the form, so the submit op requestSubmits it directly; the real
# submit event fires and on(:verify, event: "submit") intercepts it into ONE
# signed action POST. The explicit action to the nav-probe page proves
# interception — a native (un-prevented) submit would navigate away.
class VerificationCodeComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :code
  action :verify, params: { code: :string }

  reactive_compute :otp, inputs: { code: :string }, outputs: %i[code]

  def initialize(code: "")
    @code = code
  end

  def id = "verification-code"

  def verify(code:)
    @code = code
  end

  def view_template
    form(action: "/nav_probe", method: "post",
      **mix(reactive_root(compute: :otp), on(:verify, event: "submit"))) do
      input(name: "code", value: @code, inputmode: "numeric",
        autocomplete: "one-time-code", data: { testid: "code" })
      button(type: "submit", data: { testid: "verify" }) { "Verify" }
      p(data: { testid: "status" }) { @code.empty? ? "waiting" : "verified:#{@code}" }
    end
  end
end
