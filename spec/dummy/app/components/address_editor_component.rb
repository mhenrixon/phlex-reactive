# frozen_string_literal: true

# Exercises the accepts_nested_attributes_for helper (issue #24): a reactive
# editor for an Account's has_one :address. save(address:) maps straight onto
# address_attributes via nested_update!, which preserves the existing record id
# so update_only matches in place instead of building a second association.
class AddressEditorComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :account

  action :save, params: {
    address: { street: :string, city: :string, postal_code: :string, country: :string }
  }

  def initialize(account:)
    @account = account
  end

  def id = dom_id(@account, "address_editor")

  # Real apps authorize the record here (e.g. `authorize! @account, :update?` —
  # see docs/security.md); the dummy app has no authz layer, like every other
  # fixture, so the contract is demonstrated in the docs, not baked in here.
  def save(address:)
    nested_update!(:address, address)
  end

  def view_template
    div(id:, **reactive_attrs) do
      input(**reactive_field(:"address[street]", value: @account.address&.street))
      button(**mix(on(:save), data: { testid: "save" })) { "Save" }
    end
  end
end
