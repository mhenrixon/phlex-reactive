# frozen_string_literal: true

require "system_helper"

# Issue #161: reactive_show — value-conditional visibility, the x-show /
# data-show equivalent. Dependent sections show/hide from a field's CURRENT
# value entirely client-side: a fetch spy wrapped around window.fetch BEFORE
# any interaction proves the reactive endpoint is never called, and the
# no-reload marker proves the page never navigates.
RSpec.describe "Value-conditional visibility (issue #161 — reactive_show)", type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetchCount = 0
      const original = window.fetch
      window.fetch = (...args) => { window.__fetchCount += 1; return original(...args) }
    JS
  end

  it "shows/hides dependent sections from select, checkbox, and radio values — zero fetches, no reload" do
    visit "/conditional_fieldset"
    page.execute_script("window.__noReload = 'alive'")
    install_fetch_spy

    # Initial state: every dependent section is server-rendered hidden — the
    # in-root sections AND the cross-root badge outside the component (#164).
    expect(page).to have_css("[data-testid='mode-details']", visible: :hidden)
    expect(page).to have_css("[data-testid='gift-note']", visible: :hidden)
    expect(page).to have_css("[data-testid='address']", visible: :hidden)
    expect(page).to have_css("[data-testid='mode-badge']", visible: :hidden)

    # Select: visible WHILE mode != "off" (the not: predicate) — the in-root
    # panel AND the declared cross-root badge toggle from the same change.
    select "Express", from: "mode"
    expect(page).to have_css("[data-testid='mode-details']", text: "Shipping details")
    expect(page).to have_css("[data-testid='mode-badge']", text: "Shipping enabled")

    # …and hidden again when the value returns to the literal — both of them.
    select "No shipping", from: "mode"
    expect(page).to have_css("[data-testid='mode-details']", visible: :hidden)
    expect(page).to have_css("[data-testid='mode-badge']", visible: :hidden)

    # Checkbox: equals: true compares the CHECKED state, not the constant "on".
    find("[data-testid='gift']").check
    expect(page).to have_css("[data-testid='gift-note']", text: "Gift message")
    find("[data-testid='gift']").uncheck
    expect(page).to have_css("[data-testid='gift-note']", visible: :hidden)

    # Radio group: the binding reads the CHECKED radio's value.
    find("[data-testid='delivery-ship']").click
    expect(page).to have_css("[data-testid='address']", text: "Shipping address")
    find("[data-testid='delivery-pickup']").click
    expect(page).to have_css("[data-testid='address']", visible: :hidden)

    # The whole exchange was client-side: not one fetch, no full-page reload.
    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
