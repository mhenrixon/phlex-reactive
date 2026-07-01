# frozen_string_literal: true

require "rails_helper"

# The PERSISTED (server-side) half of the reactive_compute example: a persisted
# order's `rebalance` action runs the PaymentSplit twin server-side and streams
# the recomputed component back. (The NEW-draft half runs entirely in-browser and
# is covered by the JS unit test + the system spec.)
RSpec.describe "Order rebalance action", type: :request do
  let(:order) { Order.create!(total: 500, allowance: 0, cash: 500, leasing: 0) }

  it "rebalances cash server-side and persists the split" do
    post_action(
      OrderComponent,
      payload: { "gid" => order.to_gid.to_s },
      act: "rebalance",
      params: { allowance: 100, cash: 500, leasing: 0, total: 500 }
    )

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    # cash absorbed the remainder (500 - 100)
    expect(order.reload.allowance).to eq(100)
    expect(order.cash).to eq(400)
    # the streamed component reflects the new cash and refreshes the token
    expect(response.body).to include('action="replace"')
    expect(response.body).to include("data-reactive-token-value")
  end

  it "caps the edited method and zeros the peers when it exceeds the total" do
    post_action(
      OrderComponent,
      payload: { "gid" => order.to_gid.to_s },
      act: "rebalance",
      params: { allowance: 999, cash: 500, leasing: 0, total: 500 }
    )

    expect(response).to have_http_status(:ok)
    expect(order.reload.allowance).to eq(500)
    expect(order.cash).to eq(0)
    expect(order.leasing).to eq(0)
  end

  it "is default-deny for an undeclared action" do
    post_action(OrderComponent, payload: { "gid" => order.to_gid.to_s }, act: "drop_table")
    expect(response).to have_http_status(:forbidden)
  end
end
