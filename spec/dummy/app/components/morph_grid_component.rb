# frozen_string_literal: true

# Issue #28: the "edit a row, it saves" grid. Each field fires a DEBOUNCED
# `update` while the user is still typing/tabbing. The action returns
# Response.morph(self), so the row re-renders via Idiomorph — the focused input
# and its in-progress value survive the save. With a plain Response.replace this
# row would outerHTML-swap, blur the field, and drop the just-typed value.
class MorphGridComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :account

  action :update, params: {name: :string}

  def initialize(account:)
    @account = account
  end

  def id = dom_id(@account)

  # Persist the edit and morph in place. The saved value reads back from the DB
  # on the morphed render, so a Playwright test can prove the typed value
  # actually persisted (the issue's failing assertion).
  def update(name:)
    @account.update!(name:) if name.present?
    Phlex::Reactive::Response.morph(self)
  end

  def view_template
    div(id:, **reactive_attrs) do
      # The field both holds the value AND triggers the debounced update — the
      # canonical per-field reactive editing pattern from the issue.
      input(**mix(on(:update, event: "input", debounce: 150),
        name: "name", value: @account.name, data: {testid: "name"}))
      span(data: {testid: "saved"}) { @account.name }
    end
  end
end
