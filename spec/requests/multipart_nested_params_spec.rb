# frozen_string_literal: true

require "rails_helper"

# Issue #39: an explicit NESTED-hash / ARRAY param sent on the MULTIPART path
# was silently dropped. The JSON (no-file) path handled the same nested param
# correctly, so the two encodings were asymmetric.
#
# The fix is client-side (PR #38, issue #39): #buildFormData bracket-expands a
# non-scalar param into params[key][sub] / params[key][index][...] FormData
# fields instead of JSON.stringify'ing it into one params[key]='<json>' string.
# That is the SAME bracketed/index-hash shape a Rails form posts and the SAME
# shape the server's expand_bracket_keys / array_values already handle — so the
# server is UNCHANGED and the JSON and multipart paths now coerce identically.
#
# These specs post that bracketed multipart shape end-to-end and assert it
# coerces correctly (the contract the client fix relies on). nested_params_spec
# and bracket_params_spec cover the same shapes over application/json; this is
# the missing multipart coverage.
RSpec.describe "Multipart nested/array param coercion (issue #39)", type: :request do
  # A real multipart POST. Rack::Test flattens a nested hash into the bracketed
  # field names the fixed client emits (params[invoice][date], params[items][0]
  # [qty]) — the multipart encoding, not a JSON body.
  def post_multipart(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
  end

  # Pull the reflected coerced params back out of the rendered <pre> (Phlex
  # auto-escapes the JSON text, so unescape before parsing).
  def received(response)
    json = response.body[/data-testid="received">(.*?)<\/pre>/m, 1]
    JSON.parse(CGI.unescapeHTML(json))
  end

  let(:payload) { {"s" => {"received" => nil}} }

  it "coerces a nested-object param sent as multipart (the #39 bug case)" do
    post_multipart(NestedParamsComponent, payload:, act: "save_invoice",
      params: {invoice: {date: "2026-01-02", status: "open"}})

    expect(response).to have_http_status(:ok)
    expect(received(response)["invoice"]).to eq("date" => "2026-01-02", "status" => "open")
  end

  it "coerces nested types after multipart bracket expansion (float stays typed)" do
    post_multipart(NestedParamsComponent, payload:, act: "save_invoice",
      params: {invoice: {date: "2026-01-02", total: "9.99"}})

    expect(received(response)["invoice"]["total"]).to eq(9.99)
  end

  it "coerces an array-of-scalar param sent as multipart ([:integer])" do
    post_multipart(NestedParamsComponent, payload:, act: "save",
      params: {bank_account_ids: ["1", "2", "3"]})

    expect(response).to have_http_status(:ok)
    expect(received(response)["bank_account_ids"]).to eq([1, 2, 3])
  end

  it "coerces an array-of-hash param sent as multipart (Rails nested attributes)" do
    post_multipart(NestedParamsComponent, payload:, act: "save",
      params: {
        invoice_items_attributes: [
          {id: "10", quantity: "2", price: "5", _destroy: "false"},
          {id: "11", quantity: "3", price: "6", _destroy: "true"}
        ]
      })

    items = received(response)["invoice_items_attributes"]
    expect(items.map { |i| i["id"] }).to eq([10, 11])
    expect(items.map { |i| i["quantity"] }).to eq([2.0, 3.0])
    expect(items.map { |i| i["_destroy"] }).to eq([false, true])
  end

  it "drops undeclared nested keys on the multipart path too (no mass assignment)" do
    post_multipart(NestedParamsComponent, payload:, act: "save_invoice",
      params: {invoice: {date: "2026-01-02", admin: "true"}})

    expect(received(response)["invoice"].keys).to contain_exactly("date")
  end

  it "still coerces a flat scalar alongside a nested param over multipart" do
    post_multipart(NestedParamsComponent, payload:, act: "save_invoice",
      params: {date: "2026-06-27", invoice: {date: "2026-01-02"}})

    parsed = received(response)
    expect(parsed["date"]).to eq("2026-06-27")
    expect(parsed["invoice"]["date"]).to eq("2026-01-02")
  end
end
