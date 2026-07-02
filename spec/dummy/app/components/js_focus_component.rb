# frozen_string_literal: true

# Issue #97: server-pushed client DOM ops via reply.<verb>.js(...). Saving the
# first field morphs the whole component in place, then a reactive:js stream —
# emitted AFTER the morph — focuses the SECOND field. The ORDERING contract is
# the point: the op stream rides last, so focus("[name=next]") lands on the
# freshly morphed field rather than a node about to be replaced.
#
# The morph re-renders the root (its data-reactive-token-value refreshes), and
# the reactive:js stream targets the same id (self-scoped ops) WITHOUT counting
# as a self-render, so the token machinery is untouched (see the request spec).
class JsFocusComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :account

  action :save, params: { first: :string }

  def initialize(account:)
    @account = account
  end

  def id = dom_id(@account)

  # Persist the first field, morph in place, then focus the SECOND field on the
  # client. The morph reads the saved value back so the browser spec can prove
  # the round trip landed; the js op proves focus moved to the morphed field.
  def save(first:)
    @account.update!(name: first) if first.present?
    reply.morph.js(js.focus("[name=next]"))
  end

  def view_template
    div(id:, **reactive_attrs) do
      input(**mix(name: "first", value: @account.name, data: { testid: "first" }))
      # A button (not the field) triggers the save, so the FIELD that receives
      # focus is not the one the user last interacted with — the focus move is
      # unambiguously the server op, not a leftover browser default.
      button(**mix(on(:save), data: { testid: "save" })) { "Save" }
      input(name: "next", data: { testid: "next" })
      span(data: { testid: "saved" }) { @account.name }
    end
  end
end
