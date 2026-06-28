# frozen_string_literal: true

require "rails_helper"

# Issue #24: nested_update! / nested_attributes map a declared nested param onto
# <assoc>_attributes and carry the existing record id automatically, so an
# accepts_nested_attributes_for editor doesn't re-derive the *_attributes + id
# preservation boilerplate by hand (and risk a duplicate has_one build).
RSpec.describe "accepts_nested_attributes_for helper (issue #24)", type: :request do
  let(:account) { Account.create!(name: "Acme") }
  let(:component) { AddressEditorComponent.new(account:) }

  describe "#nested_attributes (the id-preserving map)" do
    it "builds <assoc>_attributes with no id when the association is absent" do
      result = component.send(:nested_attributes, :address, { street: "1 Main" })

      expect(result).to eq(address_attributes: { street: "1 Main" })
    end

    it "carries the existing record id when the association is present" do
      addr = account.create_address!(street: "old")
      result = component.send(:nested_attributes, :address, { street: "new" })

      expect(result).to eq(address_attributes: { street: "new", id: addr.id })
    end

    it "does not mutate the params it was given" do
      account.create_address!(street: "old")
      params = { street: "new" }
      component.send(:nested_attributes, :address, params)

      expect(params).to eq({ street: "new" }) # no id leaked in
    end
  end

  describe "#nested_update! (end-to-end through the action)" do
    it "creates the associated record on first save (no duplicate build)" do
      post_action(AddressEditorComponent, payload: { "gid" => account.to_gid.to_s }, act: "save",
        params: { address: { street: "1 Main", city: "Town" } })

      expect(response).to have_http_status(:ok)
      account.reload
      expect(account.address).to be_present
      expect(account.address.street).to eq("1 Main")
      expect(Address.where(account_id: account.id).count).to eq(1)
    end

    it "UPDATES the existing record in place (id preserved, no second has_one)" do
      addr = account.create_address!(street: "old", city: "Oldtown")

      post_action(AddressEditorComponent, payload: { "gid" => account.to_gid.to_s }, act: "save",
        params: { address: { street: "new", city: "Newtown" } })

      expect(response).to have_http_status(:ok)
      expect(addr.reload.street).to eq("new")
      expect(addr.reload.city).to eq("Newtown")
      # Crucial: still exactly ONE address — the id was preserved, not rebuilt.
      expect(Address.where(account_id: account.id).count).to eq(1)
      expect(account.reload.address.id).to eq(addr.id)
    end
  end
end
