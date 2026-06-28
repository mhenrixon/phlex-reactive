# frozen_string_literal: true

require "system_helper"

# Issue #46: the client #extractToken read the FIRST data-reactive-token-value in
# the response, not the one for THIS controller's element. On a collection whose
# rows are THEMSELVES reactive, an `add` response is, in body order: the appended
# ROW (carrying its OWN token) FIRST, then the container's `reactive:token` refresh
# LAST. So the list controller stored the ROW's token and its SECOND dispatch sent
# a row token → failed verification → the second add silently did nothing. The list
# was add-once-only IN THE BROWSER even though the server response was correct
# (request specs pass; only a real two-click browser test catches it).
#
# The fix reads the token that re-renders THIS element's id (the trailing
# reactive:token stream for the container), so repeated adds keep verifying.
RSpec.describe "Reactive rows — repeated adds on a collection of reactive rows (issue #46)", type: :system do
  it "adds a SECOND row after the first (the token rolls forward in the browser)" do
    visit "/reactive_rows"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='reactive-row']", count: 0)

    # FIRST add. have_css is a waiting matcher → the synchronization barrier for the
    # async append; do NOT snapshot right after the click.
    find("[data-testid='new-row']").set("first row")
    find("[data-testid='add-row']").click
    expect(page).to have_css("[data-testid='reactive-row']", count: 1)
    expect(page).to have_css("[data-testid='reactive-row']", text: "first row")

    # SECOND add — the decisive assertion. Pre-fix the list controller is holding
    # the FIRST row's token, so this dispatch 400s and NOTHING happens (count stays
    # 1). Post-fix it holds the container's refreshed token, so the add succeeds.
    find("[data-testid='new-row']").set("second row")
    find("[data-testid='add-row']").click
    expect(page).to have_css("[data-testid='reactive-row']", count: 2)
    expect(page).to have_css("[data-testid='reactive-row']", text: "second row")

    # A THIRD, to prove the token keeps rolling forward indefinitely (not just once).
    find("[data-testid='new-row']").set("third row")
    find("[data-testid='add-row']").click
    expect(page).to have_css("[data-testid='reactive-row']", count: 3)

    expect(Todo.count).to eq(3)
    # No full-page reload — every add was a reactive round trip, not a navigation.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
