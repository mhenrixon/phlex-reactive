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

    # Type a new quantity, then move to price and keep typing — exactly the
    # spreadsheet flow the issue describes.
    find("[data-testid='quantity']").set("5")
    price = find("[data-testid='price']")
    price.click # focus price as the user tabs over
    price.set("7")

    # The debounced quantity save re-streamed ONLY the total cell. The total
    # reflects the saved quantity (5 * 3 = 15) — proving the partial update
    # landed without a full-row replace.
    expect(page).to have_css("[data-testid='total']", text: "15")

    # The decisive assertion: price is STILL the active element. A full-self
    # replace would have swapped the whole row's outerHTML and blurred it.
    active_testid = page.evaluate_script("document.activeElement && document.activeElement.dataset.testid")
    expect(active_testid).to eq("price")

    # ...and price still holds the value the user typed (not reset to the stale
    # server value of 3).
    expect(page).to have_field("price", with: "7")

    # The token rolled forward, so the SECOND field's debounced save also lands:
    # the price persists and the total recomputes (5 * 7 = 35) on its own cell.
    expect(page).to have_css("[data-testid='total']", text: "35")
    expect(item.reload.price).to eq(7)
    expect(item.quantity).to eq(5)

    # No full-page reload happened.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
