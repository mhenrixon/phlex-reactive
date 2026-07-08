# frozen_string_literal: true

require "rails_helper"

# Issue #208 (JSON mode): reactive_nested_list(as: :json) — for an app whose
# controller parses a serialized JSON param instead of Rails'
# accepts_nested_attributes_for. The GET renders the SAME client wiring plus the
# json-mode marker + the hidden field the client keeps in sync; the POST proves
# a hand-rolled JSON.parse controller path (NO nested attributes) reconciles the
# parent + rows in ONE request — the app never rewires its persistence.
RSpec.describe "Draft order form — JSON mode (nested rows)", type: :request do
  describe "GET /draft_order_json" do
    it "renders the json-mode markers + the synced hidden field (still tokenless)" do
      get "/draft_order_json"

      expect(response).to have_http_status(:ok)
      body = response.body
      # The plain list marker is still there (nestedAdd/Remove key on it)…
      expect(body).to include('data-reactive-nested-list="line_items"')
      # …plus the json-mode marker and the hidden-field selector.
      expect(body).to include('data-reactive-nested-json="line_items"')
      expect(body).to include('data-reactive-nested-json-field="[name=&quot;order[line_items]&quot;]"')
        .or include('data-reactive-nested-json-field="[name="order[line_items]"]"')
      # The hidden JSON field itself (the client's single source of truth).
      expect(body).to include('name="order[line_items]"')
      # Pure form state — a ClientBindings root ships no signed token.
      expect(body).not_to include("data-reactive-token-value")
    end
  end

  describe "POST /orders_json (a hand-rolled JSON.parse reconcile — no nested attributes)" do
    it "creates the order + rows from ONE serialized JSON param" do
      post "/orders_json", params: {
        order: {
          total: 500,
          line_items: [{ quantity: 3, price: 42 }, { quantity: 1, price: 9 }].to_json
        }
      }

      expect(response).to have_http_status(:ok)
      order = Order.last
      expect(order.total).to eq(500)
      expect(order.line_items.map { [it.quantity, it.price] }).to contain_exactly([3, 42], [1, 9])
    end

    it "creates the order with NO rows when the JSON array is empty" do
      post "/orders_json", params: { order: { total: 100, line_items: "[]" } }

      expect(response).to have_http_status(:ok)
      expect(Order.last.line_items).to be_empty
    end
  end
end
