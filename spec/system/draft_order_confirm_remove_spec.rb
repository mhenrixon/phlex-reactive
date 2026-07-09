# frozen_string_literal: true

require "system_helper"

# End-to-end proof of reactive_nested_remove(confirm:) on a JSON-mode draft list
# (issue #218): the per-row remove gates behind the overridable confirmResolver
# (default window.confirm), no bespoke JS.
#
#   * Declining leaves the row in the DOM AND in the hidden JSON field (an
#     un-removed row is still serialized) — nothing round-trips.
#   * Accepting removes the row and re-syncs the JSON field (an absent row IS
#     the removal), then the REAL submit persists only the survivors.
#
# window.confirm is overridden in the page so accept/decline is deterministic
# across both drivers and both servers (Puma + Falcon) — the gate is what's
# under test, not the native dialog chrome.
RSpec.describe "Draft order form — confirm on remove (issue #218)", type: :system do
  def json_field_value
    JSON.parse(page.find("[data-testid='json-field']", visible: false).value)
  end

  def add_two_filled_rows
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 2)

    rows = page.all("[data-testid='item-row']")
    rows[0].find("[data-testid='qty']").set(9)
    rows[0].find("[data-testid='price']").set(999)
    rows[1].find("[data-testid='qty']").set(3)
    rows[1].find("[data-testid='price']").set(42)
    rows
  end

  it "declining the confirm keeps the row and its JSON entry (nothing removed)" do
    visit "/draft_order_confirm_remove"
    expect(page).to have_css("[data-testid='add-item']")
    page.execute_script("window.__noReload = 'alive'")
    rows = add_two_filled_rows

    expect(json_field_value).to contain_exactly(
      { "quantity" => "9", "price" => "999" },
      { "quantity" => "3", "price" => "42" }
    )

    # Decline → the row stays, the JSON array is unchanged, no navigation.
    page.execute_script("window.confirm = () => false")
    rows[0].find("[data-testid='remove-item']").click

    expect(page).to have_css("[data-testid='item-row']", count: 2)
    expect(json_field_value).to contain_exactly(
      { "quantity" => "9", "price" => "999" },
      { "quantity" => "3", "price" => "42" }
    )
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "accepting the confirm removes the row, re-syncs JSON, and persists survivors" do
    visit "/draft_order_confirm_remove"
    expect(page).to have_css("[data-testid='add-item']")
    rows = add_two_filled_rows

    # Accept → the first row leaves the DOM and the JSON array.
    page.execute_script("window.confirm = () => true")
    rows[0].find("[data-testid='remove-item']").click

    expect(page).to have_css("[data-testid='item-row']", count: 1)
    expect(json_field_value).to eq([{ "quantity" => "3", "price" => "42" }])

    # The REAL submit reconciles from the JSON param: only the survivor persists.
    find("[data-testid='total']").set(500)
    find("[data-testid='create-order']").click

    expect(page).to have_css("[data-testid='order-created']")
    expect(page).to have_css("[data-testid='item-count']", text: "1")
    expect(page).to have_css("[data-testid='created-item']", text: "3 × 42")

    order = Order.last
    expect(order.total).to eq(500)
    expect(order.line_items.map { [it.quantity, it.price] }).to eq([[3, 42]])
  end
end
