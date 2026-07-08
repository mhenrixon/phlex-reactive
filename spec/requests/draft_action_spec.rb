# frozen_string_literal: true

require "rails_helper"

# Issue #208: a server action against a DRAFT (unsaved-parent) token. The token
# carries no gid — Component::Identity omits it for an unpersisted record — so
# from_identity must rebuild through the record kwarg's initialize default
# (OrderComponent defaults to a fresh Order.new) and the signed state, run the
# action, and re-render WITHOUT touching the database. Before the fix this
# 500'd on the absent gid at the very first draft action.
RSpec.describe "Draft (unsaved parent) action round trip", type: :request do
  it "runs the action against the rebuilt draft and re-renders (no gid, no DB write)" do
    post_action(
      OrderComponent,
      payload: { "s" => { "total" => 500, "allowance" => 0, "cash" => 500, "leasing" => 0 } },
      act: "rebalance",
      params: { allowance: 200, cash: 500, leasing: 0, total: 500 }
    )

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    # The draft re-rendered with the rebalanced split (cash absorbed 500 - 200)…
    expect(response.body).to include('target="order-draft"')
    expect(response.body).to include('value="300"')
    # …and a fresh draft token (still gid-less) rides the re-render.
    expect(response.body).to include("data-reactive-token-value")
    # Nothing persisted — the draft stays a draft.
    expect(Order.count).to eq(0)
  end

  it "stays default-deny for an undeclared action on a draft token" do
    post_action(OrderComponent, payload: { "s" => { "total" => 500 } }, act: "drop_table")

    expect(response).to have_http_status(:forbidden)
  end
end
