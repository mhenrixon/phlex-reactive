# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of the draft nested-attribute rows (issue #208):
#
#   * The pre-save window is pure CLIENT-SIDE form state — the fetch spy proves
#     ZERO action POSTs across adding, typing, and removing rows; there is no
#     persisted parent, no token, nothing to round-trip.
#   * Add clones the server-owned <template> row and renumbers its field names
#     (distinct indexes per row); remove deletes the draft row from the DOM —
#     all without a page reload (the window marker survives).
#   * The REAL form submit posts order[line_items_attributes][<index>][…] and
#     accepts_nested_attributes_for creates the order + rows in ONE request —
#     the removed row never reaches the server.
#
# One generic controller, no per-feature JavaScript — the wiring is
# reactive_nested_list/template on the containers and reactive_nested_add/
# remove on the buttons.
RSpec.describe "Draft order form (nested rows)", type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS
  end

  it "adds and removes draft rows client-side, then persists the survivors in one submit" do
    visit "/draft_order"
    expect(page).to have_css("[data-testid='add-item']")
    install_fetch_spy

    # Add two rows — each clone gets its own renumbered field names.
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 2)

    names = page.all("[data-testid='qty']").map { it[:name] }
    expect(names.uniq.length).to eq(2)
    expect(names).to all(match(/\Aorder\[line_items_attributes\]\[\d+\]\[quantity\]\z/))

    # Fill both rows, then remove the FIRST — its values must never persist.
    rows = page.all("[data-testid='item-row']")
    rows[0].find("[data-testid='qty']").set(9)
    rows[0].find("[data-testid='price']").set(999)
    rows[1].find("[data-testid='qty']").set(3)
    rows[1].find("[data-testid='price']").set(42)

    rows[0].find("[data-testid='remove-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)

    # The whole pre-save window round-tripped NOTHING and never reloaded.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    # The REAL submit reconciles: one request, parent + surviving row.
    find("[data-testid='total']").set(500)
    find("[data-testid='create-order']").click

    expect(page).to have_css("[data-testid='order-created']")
    expect(page).to have_css("[data-testid='item-count']", text: "1")
    expect(page).to have_css("[data-testid='created-item']", text: "3 × 42")

    order = Order.last
    expect(order.total).to eq(500)
    expect(order.line_items.map { [it.quantity, it.price] }).to eq([[3, 42]])
  end

  it "submits an order with NO rows when none were added (no fabricated empties)" do
    visit "/draft_order"
    expect(page).to have_css("[data-testid='add-item']")

    find("[data-testid='total']").set(100)
    find("[data-testid='create-order']").click

    expect(page).to have_css("[data-testid='order-created']")
    expect(page).to have_css("[data-testid='item-count']", text: "0")
    expect(Order.last.line_items).to be_empty
  end
end
