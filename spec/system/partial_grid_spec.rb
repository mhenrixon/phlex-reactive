# frozen_string_literal: true

require "system_helper"

# Issue #30: per-field editing in a grid must NOT tear down a sibling input when
# a debounced save fires. The action re-streams ONLY the total cell via
# reply.streams (a partial update + a token-only refresh) — NOT a full-self
# replace. So the user can type a quantity, tab to price, and keep typing: the
# quantity field's debounced save updates the total without blurring price or
# dropping its in-flight value. The token still rolls forward (via the inert
# reactive:token stream), so the SECOND field's save verifies too.
RSpec.describe "Partial grid — a partial save keeps sibling inputs live (issue #30)", type: :system do
  it "updates only the total cell and leaves the focused sibling input untouched" do
    item = LineItem.create!(quantity: 2, price: 3)
    visit "/partial_grid/#{item.id}"
    page.execute_script("window.__noReload = 'alive'")

    # FIRST save: edit quantity while it's focused. Wait for the partial save to
    # FULLY settle (the total cell becomes 5 * 3 = 15) BEFORE touching price — so
    # the two debounced saves are sequenced and neither intermediate state is a
    # transient that a fast CI run could skip past. have_css is a waiting matcher,
    # so this is the synchronization barrier, not a snapshot.
    quantity = find("[data-testid='quantity']")
    quantity.click
    quantity.set("5")
    expect(page).to have_css("[data-testid='total']", text: "15") # partial save #1 landed

    # The partial save re-streamed ONLY the total cell — so the quantity field the
    # user just edited is STILL the active element (a full-row replace would have
    # swapped the row's outerHTML and blurred it).
    active_testid = page.evaluate_script("document.activeElement && document.activeElement.dataset.testid")
    expect(active_testid).to eq("quantity")
    expect(page).to have_field("quantity", with: "5") # caret/value preserved

    # SECOND save: now move to price and edit it. The token rolled forward via the
    # inert reactive:token stream (NOT a self replace), so this save also verifies.
    price = find("[data-testid='price']")
    price.click
    price.set("7")
    expect(page).to have_css("[data-testid='total']", text: "35") # partial save #2 landed (5 * 7)

    # Price kept focus + its typed value across its own partial save too.
    active_testid = page.evaluate_script("document.activeElement && document.activeElement.dataset.testid")
    expect(active_testid).to eq("price")
    expect(page).to have_field("price", with: "7")

    # Both edits persisted (proves the token kept verifying across both saves).
    expect(item.reload.quantity).to eq(5)
    expect(item.price).to eq(7)

    # No full-page reload happened.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
