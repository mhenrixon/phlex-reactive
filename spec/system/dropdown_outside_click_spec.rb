# frozen_string_literal: true

require "system_helper"

# Issue #80: on(:close_menu, outside: true) — the close-a-dropdown-on-outside-
# click pattern. The trigger is window-bound; a click INSIDE the component's
# root is a complete client-side no-op, a click outside fires the action, and
# the window binding never preventDefaults — so native navigation elsewhere on
# the page keeps working while the menu is mounted.
RSpec.describe "Outside-click dropdown (issue #80)", type: :system do
  it "closes on an outside click; an inside click is a complete no-op" do
    visit "/dropdown"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='closes']", text: "0")
    expect(page).to have_no_css("[data-testid='menu']")

    # Open the menu (an ordinary element-bound trigger).
    find("[data-testid='menu-button']").click
    expect(page).to have_css("[data-testid='menu']")

    # A click INSIDE the open menu must not fire close_menu (the outside guard
    # bails before anything happens). The proof comes below: the closes counter
    # lands on exactly 1 after the outside click — an inside dispatch would
    # have made it 2.
    find("[data-testid='menu-item']").click
    expect(page).to have_css("[data-testid='menu']")

    # A click OUTSIDE the root closes the menu via the reactive action.
    find("[data-testid='outside-area']").click
    expect(page).to have_no_css("[data-testid='menu']")
    expect(page).to have_css("[data-testid='closes']", text: "1")

    # The whole exchange was reactive round trips, never a full-page reload.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "does not preventDefault native link navigation while the menu is open" do
    visit "/dropdown"
    find("[data-testid='menu-button']").click
    expect(page).to have_css("[data-testid='menu']")

    # With the window-bound close listener mounted, clicking a link elsewhere
    # on the page must still NAVIGATE — the client only preventDefaults
    # element-bound triggers, never window-bound ones.
    find("[data-testid='outside-link']").click
    expect(page).to have_css("[data-testid='nav-probe']", text: "NAVIGATED")
  end
end
