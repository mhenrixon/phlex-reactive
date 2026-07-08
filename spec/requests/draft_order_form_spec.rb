# frozen_string_literal: true

require "rails_helper"

# Issue #208: the draft nested-attribute rows form — the server half. The GET
# renders the client wiring (list container, template row with placeholder
# names, add/remove triggers — and NO token: the rows are pure form state);
# the POST is the reconcile contract: order[line_items_attributes][<index>][…]
# creates the order + rows in ONE request via accepts_nested_attributes_for.
RSpec.describe "Draft order form (nested rows)", type: :request do
  describe "GET /draft_order" do
    it "renders the nested-rows wiring with scope-aware placeholder names" do
      get "/draft_order"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('data-reactive-nested-list="line_items"')
      expect(body).to include('data-reactive-nested-template="line_items"')
      expect(body).to include("click-&gt;reactive#nestedAdd").or include("click->reactive#nestedAdd")
      expect(body).to include('data-reactive-association-param="line_items"')
      # The template row's names carry the placeholder, scoped under order[…].
      expect(body).to include("order[line_items_attributes][NEW_ROW][quantity]")
      expect(body).to include("order[line_items_attributes][NEW_ROW][price]")
      # Pure form state — a ClientBindings root ships no signed token.
      expect(body).not_to include("data-reactive-token-value")
    end
  end

  describe "POST /orders (the reconcile)" do
    it "creates the order + rows in ONE request from the indexed nested params" do
      post "/orders", params: {
        order: {
          total: 500,
          line_items_attributes: {
            "1751970000000" => { quantity: 3, price: 42 },
            "1751970000001" => { quantity: 1, price: 9 }
          }
        }
      }

      expect(response).to have_http_status(:ok)
      order = Order.last
      expect(order.total).to eq(500)
      expect(order.line_items.map { [it.quantity, it.price] }).to contain_exactly([3, 42], [1, 9])
    end

    it "creates the order with NO rows when none were added (no fabricated empties)" do
      post "/orders", params: { order: { total: 100 } }

      expect(response).to have_http_status(:ok)
      expect(Order.last.line_items).to be_empty
    end
  end
end
