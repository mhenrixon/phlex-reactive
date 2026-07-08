# frozen_string_literal: true

require "system_helper"

# End-to-end proof of JSON-mode draft nested rows (issue #208):
#
#   * The pre-save window is pure CLIENT-SIDE form state — the fetch spy proves
#     ZERO action POSTs across adding, typing, and removing rows.
#   * The client mirrors the rows into ONE hidden field (order[line_items]) as a
#     JSON array on every add / keystroke / remove — the widget's single source
#     of truth. We read the field to prove the projection.
#   * The REAL form submit posts that JSON param, and a hand-rolled JSON.parse
#     controller (NO accepts_nested_attributes_for) reconciles parent + rows —
#     the removed row never reaches the server.
RSpec.describe "Draft order form — JSON mode (nested rows)", type: :system do
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

  def json_field_value
    JSON.parse(page.find("[data-testid='json-field']", visible: false).value)
  end

  it "syncs rows into the hidden JSON field client-side, then persists the survivors in one submit" do
    visit "/draft_order_json"
    expect(page).to have_css("[data-testid='add-item']")
    install_fetch_spy

    # Add two rows — the empty rows land in the field immediately.
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 2)

    # Fill both rows; the hidden field re-serializes on every keystroke.
    rows = page.all("[data-testid='item-row']")
    rows[0].find("[data-testid='qty']").set(9)
    rows[0].find("[data-testid='price']").set(999)
    rows[1].find("[data-testid='qty']").set(3)
    rows[1].find("[data-testid='price']").set(42)

    # The client projection carries both rows, keys inferred from the names.
    expect(json_field_value).to contain_exactly(
      { "quantity" => "9", "price" => "999" },
      { "quantity" => "3", "price" => "42" }
    )

    # Remove the FIRST row — it leaves the JSON array (an absent row IS removal).
    rows[0].find("[data-testid='remove-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)
    expect(json_field_value).to eq([{ "quantity" => "3", "price" => "42" }])

    # The whole pre-save window round-tripped NOTHING and never reloaded.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    # The REAL submit reconciles from the JSON param: one request, surviving row.
    find("[data-testid='total']").set(500)
    find("[data-testid='create-order']").click

    expect(page).to have_css("[data-testid='order-created']")
    expect(page).to have_css("[data-testid='item-count']", text: "1")
    expect(page).to have_css("[data-testid='created-item']", text: "3 × 42")

    order = Order.last
    expect(order.total).to eq(500)
    expect(order.line_items.map { [it.quantity, it.price] }).to eq([[3, 42]])
  end

  it "submits an order with an empty JSON array when no rows were added" do
    visit "/draft_order_json"
    expect(page).to have_css("[data-testid='add-item']")

    find("[data-testid='total']").set(100)
    find("[data-testid='create-order']").click

    expect(page).to have_css("[data-testid='order-created']")
    expect(page).to have_css("[data-testid='item-count']", text: "0")
    expect(Order.last.line_items).to be_empty
  end
end
