# frozen_string_literal: true

require "rails_helper"

# Issue #218: reactive_nested_remove(confirm:) on a JSON-mode draft list — the
# server half. The GET renders the confirm wire on the remove trigger (still
# tokenless, still client-only); the confirm gate lives entirely in the client.
RSpec.describe "Draft order form — confirm on remove", type: :request do
  describe "GET /draft_order_confirm_remove" do
    it "renders the static confirm message on the remove trigger" do
      get "/draft_order_confirm_remove"

      expect(response).to have_http_status(:ok)
      body = response.body
      # The confirm rides the SAME data-reactive-confirm-param the other triggers use.
      expect(body).to include('data-reactive-confirm-param="Really remove this line item?"')
      # It's still the client-only remove trigger + a JSON-mode list.
      expect(body).to include("click-&gt;reactive#nestedRemove").or include("click->reactive#nestedRemove")
      expect(body).to include('data-reactive-nested-json="line_items"')
      # No signed token — the whole widget is pre-save form state.
      expect(body).not_to include("data-reactive-token-value")
    end
  end
end
