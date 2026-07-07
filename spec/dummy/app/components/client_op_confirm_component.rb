# frozen_string_literal: true

# Issue #178: confirm: on on_client. A purely presentational, zero-round-trip
# client op that is still destructive-feeling (clearing a draft) — gated behind
# the SAME themed confirmResolver on(:action, confirm:) uses. The op sets a
# visible marker's text via js.text; the system spec overrides window.confirm to
# prove DECLINING leaves the marker untouched (the op never ran, no navigation)
# while ACCEPTING runs it. It declares NO actions — a fetch spy proves nothing
# is ever posted, on either path.
class ClientOpConfirmComponent < ApplicationComponent
  include Phlex::Reactive::Component

  def id = "client-op-confirm"

  def view_template
    div(**reactive_root) do
      # The op clears this marker's text — the observable "did the client op run".
      span(id: "co-draft", data: { testid: "draft" }) { "unsaved draft" }

      button(**mix(
        on_client(:click, js.text("#co-draft", ""), confirm: "Discard this draft?"),
        data: { testid: "clear" }
      )) { "Clear" }
    end
  end
end
