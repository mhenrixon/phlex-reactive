# frozen_string_literal: true

require "rails_helper"

# Issue #21: a model-scoped Rails form posts FLAT bracketed keys
# (invoice[date]=…, invoice[status]=…) because #collectFields keeps the input's
# `name` verbatim. The server's coerce_hash does exact-key matching, so a nested
# schema (params: { invoice: { date: :string } }) looked for the literal key
# "invoice" and dropped everything. to_param_hash now expands bracket notation
# ("invoice[date]" => { "invoice" => { "date" => … } }) before coercion, so a
# nested schema matches a normal Rails form with zero field renaming.
RSpec.describe "Flat bracketed param coercion (issue #21)", type: :request do
  def token_for(klass, payload)
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  def post_action(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}
  end

  def received(response)
    json = response.body[/data-testid="received">(.*?)<\/pre>/m, 1]
    JSON.parse(CGI.unescapeHTML(json))
  end

  let(:payload) { {"s" => {"received" => nil}} }

  it "expands a model-scoped bracket key into the nested schema (the cosmos case)" do
    # Exactly what a Rails Form(model: @invoice) posts via #collectFields.
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {"invoice[date]" => "2026-01-02", "invoice[status]" => "open"})

    expect(response).to have_http_status(:ok)
    expect(received(response)["invoice"]).to eq("date" => "2026-01-02", "status" => "open")
  end

  it "coerces nested types after bracket expansion (integer/float stay typed)" do
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {"invoice[date]" => "2026-01-02", "invoice[total]" => "9.99"})

    invoice = received(response)["invoice"]
    expect(invoice["total"]).to eq(9.99)
  end

  it "drops undeclared bracketed keys (no mass assignment)" do
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {"invoice[date]" => "2026-01-02", "invoice[admin]" => "true"})

    expect(received(response)["invoice"].keys).to contain_exactly("date")
  end

  it "expands a bracketed array-of-hash key (Rails nested attributes)" do
    post_action(NestedParamsComponent, payload:, act: "save",
      params: {
        "invoice_items_attributes[0][id]" => "10",
        "invoice_items_attributes[0][quantity]" => "2",
        "invoice_items_attributes[0][price]" => "5",
        "invoice_items_attributes[0][_destroy]" => "false",
        "invoice_items_attributes[1][id]" => "11",
        "invoice_items_attributes[1][quantity]" => "3",
        "invoice_items_attributes[1][price]" => "6",
        "invoice_items_attributes[1][_destroy]" => "true"
      })

    items = received(response)["invoice_items_attributes"]
    expect(items.map { |i| i["id"] }).to eq([10, 11])
    expect(items.map { |i| i["quantity"] }).to eq([2.0, 3.0])
    expect(items.map { |i| i["_destroy"] }).to eq([false, true])
  end

  it "mixes a flat scalar with bracketed keys in one payload" do
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {"date" => "2026-06-27", "invoice[date]" => "2026-01-02"})

    parsed = received(response)
    expect(parsed["date"]).to eq("2026-06-27")
    expect(parsed["invoice"]["date"]).to eq("2026-01-02")
  end

  it "still accepts a PRE-NESTED object (backwards compatible with #16)" do
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {invoice: {date: "2026-01-02", status: "open"}})

    expect(received(response)["invoice"]).to eq("date" => "2026-01-02", "status" => "open")
  end

  it "preserves a non-string value (checkbox boolean) through expansion" do
    post_action(NestedParamsComponent, payload:, act: "save_invoice",
      params: {"invoice[date]" => "2026-01-02", "invoice[active]" => true})

    expect(received(response)["invoice"]["active"]).to be(true)
  end
end
