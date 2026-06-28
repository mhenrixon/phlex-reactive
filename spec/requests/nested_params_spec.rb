# frozen_string_literal: true

require "rails_helper"

# Issue #16: action param schemas can declare ARRAY and NESTED-HASH types, not
# just scalars, so a reactive action can receive Rails-style nested attributes
# (invoice[invoice_items_attributes][i][...]) or array params (ids[]) in one call.
RSpec.describe "Nested/array param coercion (issue #16)", type: :request do
  # Pull the reflected coerced params back out of the rendered <pre>. Phlex
  # auto-escapes the JSON text, so unescape before parsing.
  def received(response)
    json = response.body[/data-testid="received">(.*?)<\/pre>/m, 1]
    JSON.parse(CGI.unescapeHTML(json))
  end

  let(:payload) { {"s" => {"received" => nil}} }

  it "coerces an array-of-scalar param ([:integer])" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {bank_account_ids: ["1", "2", "3"]})

    expect(response).to have_http_status(:ok)
    expect(received(response)["bank_account_ids"]).to eq([1, 2, 3])
  end

  it "coerces an array-of-hash param with per-field types (nested attributes)" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {
        invoice_items_attributes: [
          {id: "10", quantity: "2.5", price: "9.99", _destroy: "false"},
          {id: "11", quantity: "1", price: "100", _destroy: "true"}
        ]
      })

    expect(response).to have_http_status(:ok)
    items = received(response)["invoice_items_attributes"]
    expect(items).to eq([
      {"id" => 10, "quantity" => 2.5, "price" => 9.99, "_destroy" => false},
      {"id" => 11, "quantity" => 1.0, "price" => 100.0, "_destroy" => true}
    ])
  end

  it "drops nested keys not declared in the inner schema (no mass assignment)" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {
        invoice_items_attributes: [
          {id: "10", quantity: "2", price: "5", _destroy: "false", admin: "true", secret: "x"}
        ]
      })

    item = received(response)["invoice_items_attributes"].first
    expect(item.keys).to contain_exactly("id", "quantity", "price", "_destroy")
    expect(item).not_to have_key("admin")
    expect(item).not_to have_key("secret")
  end

  it "accepts a Rails-style index hash for an array param ({\"0\"=>..., \"1\"=>...})" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {
        invoice_items_attributes: {
          "0" => {id: "10", quantity: "2", price: "5", _destroy: "false"},
          "1" => {id: "11", quantity: "3", price: "6", _destroy: "false"}
        }
      })

    items = received(response)["invoice_items_attributes"]
    expect(items.map { |i| i["id"] }).to eq([10, 11])
    expect(items.map { |i| i["quantity"] }).to eq([2.0, 3.0])
  end

  it "leaves a declared array param absent when the client omits it" do
    post_action(NestedParamsComponent, payload:, act: "save", params: {date: "2026-06-27"})

    parsed = received(response)
    expect(parsed["date"]).to eq("2026-06-27")
    # Omitted keys never reach the method → its keyword default (nil) applies.
    expect(parsed["bank_account_ids"]).to be_nil
    expect(parsed["invoice_items_attributes"]).to be_nil
  end

  it "coerces an empty array to an empty array (not dropped)" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {bank_account_ids: []})

    expect(received(response)["bank_account_ids"]).to eq([])
  end

  it "drops a malformed (non-array) array param instead of coercing it to []" do
    # A scalar sent for an array param must NOT become [] — otherwise an action
    # doing update!(bank_account_ids:) would read it as an explicit "clear all".
    # Drop it so the method's keyword default (nil) applies, distinct from a real
    # empty array.
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {bank_account_ids: "5"})

    expect(response).to have_http_status(:ok)
    expect(received(response)["bank_account_ids"]).to be_nil
  end

  it "drops a malformed (non-array) array-of-hash param" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {invoice_items_attributes: "not-an-array"})

    expect(response).to have_http_status(:ok)
    expect(received(response)["invoice_items_attributes"]).to be_nil
  end

  it "still coerces flat scalars alongside nested params" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {date: "2026-06-27", bank_account_ids: ["7"]})

    parsed = received(response)
    expect(parsed["date"]).to eq("2026-06-27")
    expect(parsed["bank_account_ids"]).to eq([7])
  end
end
