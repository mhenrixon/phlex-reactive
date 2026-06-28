# frozen_string_literal: true

require "system_helper"

# The real browser loop for the reactive_collection helper (issue #35): add a
# row and it streams in with the count bumped and the empty-state cleared;
# dismiss the last row and it leaves with the count dropped and the empty-state
# restored — all without a full-page reload.
RSpec.describe "Notifications (reactive_collection)", type: :system do
  it "adds a row, bumps the count, and clears the empty-state" do
    visit "/notifications"

    # Empty-state on first paint.
    expect(page).to have_css("[data-testid='empty-state']")
    expect(page).to have_css("[data-testid='count']", text: "0")

    # Prove no full-page reload happens across the reactive round trip.
    page.execute_script("window.__marker = 'kept'")

    find("[data-testid='new-notification']").set("deploy finished")
    find("[data-testid='add']").click

    expect(page).to have_css("[data-testid='notification']", count: 1)
    expect(page).to have_css("[data-testid='notification']", text: "deploy finished")
    expect(page).to have_css("[data-testid='count']", text: "1")
    expect(page).to have_no_css("[data-testid='empty-state']")

    expect(page.evaluate_script("window.__marker")).to eq("kept")
    expect(Todo.count).to eq(1)
  end

  it "dismisses the last row, drops the count, and restores the empty-state" do
    Todo.create!(title: "stale alert")
    visit "/notifications"

    expect(page).to have_css("[data-testid='notification']", count: 1)
    expect(page).to have_css("[data-testid='count']", text: "1")

    within first("[data-testid='notification']") do
      find("[data-testid='dismiss']").click
    end

    expect(page).to have_css("[data-testid='notification']", count: 0)
    expect(page).to have_css("[data-testid='count']", text: "0")
    expect(page).to have_css("[data-testid='empty-state']")
    expect(Todo.count).to eq(0)
  end

  it "keeps the count accurate across an add then a dismiss" do
    visit "/notifications"

    find("[data-testid='new-notification']").set("one")
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='count']", text: "1")

    # The SECOND add dispatches from the SAME list root as the first — so it only
    # succeeds if the first reply rolled the container's signed token forward.
    # Before the cosmos#1939 fix this 400'd silently (stale token) and the count
    # stuck at 1: the add-once-only bug. Reaching "2" proves the token refreshed.
    find("[data-testid='new-notification']").set("two")
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='count']", text: "2")
    expect(page).to have_css("[data-testid='notification']", count: 2)

    within first("[data-testid='notification']") do
      find("[data-testid='dismiss']").click
    end
    expect(page).to have_css("[data-testid='count']", text: "1")
    expect(page).to have_css("[data-testid='notification']", count: 1)
  end
end
