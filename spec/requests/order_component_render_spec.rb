# frozen_string_literal: true

require "rails_helper"

# Renders OrderComponent through a real request (needs the DB for persisted?)
# and asserts the new-vs-persisted wiring split: a NEW draft carries the
# reactive_compute binding + the client-only recompute action; a PERSISTED order
# carries the reactive rebalance dispatch (server reconciles).
RSpec.describe "OrderComponent render (new vs persisted)", type: :request do
  # Render via the demo pages so the component goes through a real view context.
  describe "a NEW (unsaved) order at /new_order" do
    before { get "/new_order" }

    it "renders the compute binding on the root (client-side split, no round trip)" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-reactive-compute-reducer-param="payment_split"')
      expect(response.body).to include("data-reactive-compute-inputs-param")
      expect(response.body).to include("data-reactive-compute-outputs-param")
    end

    it "wires the allowance field to the client recompute (input), not a POST" do
      root = response.body[%r{<div [^>]*data-reactive-compute-reducer-param[^>]*>.*?</div>}m] || response.body
      expect(root).to include("input-&gt;reactive#recompute").or include("input->reactive#recompute")
    end

    it "uses the stable draft id (no GlobalID for an unsaved record)" do
      expect(response.body).to include('id="order-draft"')
    end
  end

  describe "a PERSISTED order at /order/:id" do
    let(:order) { Order.create!(total: 500, allowance: 0, cash: 500, leasing: 0) }

    before { get "/order/#{order.id}" }

    it "does NOT render the compute binding (server owns the split)" do
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-reactive-compute-reducer-param")
    end

    it "wires the allowance field to the reactive rebalance dispatch on change" do
      expect(response.body).to include("change-&gt;reactive#dispatch").or include("change->reactive#dispatch")
      expect(response.body).to include("rebalance")
    end
  end
end
