# frozen_string_literal: true

require "system_helper"

# Issue #95: on_client + js ops — declarative interactivity with ZERO server
# round trips. A fetch spy wraps window.fetch BEFORE any interaction: the
# reactive endpoint (or anything else) is never called — tabs switch, the menu
# toggles, and the outside click closes it, all locally. Client ops are
# ephemeral by design (a server re-render would reset them); this component
# declares no actions at all, so there is nothing to re-render it.
RSpec.describe "Client-only ops (issue #95 — on_client + js)", type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetchCount = 0
      const original = window.fetch
      window.fetch = (...args) => { window.__fetchCount += 1; return original(...args) }
    JS
  end

  it "switches tabs and closes the menu on outside click — zero fetches, no reload" do
    visit "/client_tabs"
    page.execute_script("window.__noReload = 'alive'")
    install_fetch_spy

    # Initial state: panel 1 shown, panel 2 hidden.
    expect(page).to have_css("[data-testid='panel-1']")
    expect(page).to have_css("[data-testid='panel-2']", visible: :hidden)

    # Tab switch: hide-all + show-one + class swap, purely client-side.
    find("[data-testid='tab-2']").click
    expect(page).to have_css("[data-testid='panel-2']")
    expect(page).to have_css("[data-testid='panel-1']", visible: :hidden)
    expect(page).to have_css("#ct-tab-2.active")
    expect(page).to have_no_css("#ct-tab-1.active")

    # The menu opens via a client op…
    find("[data-testid='menu-open']").click
    expect(page).to have_css("[data-testid='menu']")

    # …a click INSIDE the root leaves it open (the outside guard bails)…
    find("[data-testid='tab-1']").click
    expect(page).to have_css("[data-testid='menu']")
    expect(page).to have_css("[data-testid='panel-1']") # the tab op still ran

    # …and a click OUTSIDE the component closes it (window-bound on_client).
    find("[data-testid='outside-area']").click
    expect(page).to have_css("[data-testid='menu']", visible: :hidden)

    # The whole exchange was client-side: not one fetch, no full-page reload.
    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  # Issue #96: the transition op reveals the drawer with an animated fade, the
  # attr op flips aria-expanded on the root, and the focus op lands on the
  # drawer's first control — all client-side, zero fetches.
  it "opens a drawer with a transition, sets aria-expanded, and focuses the first control" do
    visit "/client_tabs"
    install_fetch_spy

    expect(page).to have_css("[data-testid='drawer']", visible: :hidden)

    find("[data-testid='drawer-open']").click

    # The transition op flipped `hidden` and applied the end-state class; the
    # drawer is now visible (Capybara waits through the 40ms fade).
    expect(page).to have_css("[data-testid='drawer']")
    # The attr op set aria-expanded="true" on the reactive root.
    expect(page).to have_css("#client-tabs[aria-expanded='true']")
    # The focus op landed on the drawer's first focusable control.
    expect(page.evaluate_script("document.activeElement.dataset.testid")).to eq("drawer-first")

    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
  end
end
