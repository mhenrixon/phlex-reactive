# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of client-side option filtering (issue #163):
#
#   * The whole catalog preloads; typing in the search input shows/hides
#     options IN-BROWSER by their data-reactive-filter-text haystack — the
#     fetch spy proves ZERO action POSTs across a full type.
#   * A group whose every option filters out collapses; the empty node reveals
#     at 0 matches (both client-side).
#   * It composes with reactive_listnav (Arrow keys skip hidden options — no
#     round trip) and each option's own on(:select) trigger — SELECTION is
#     still a signed reactive action (exactly one POST).
#
# One generic controller, no per-combobox JavaScript — the wiring is
# reactive_filter on the root + reactive_listnav on the input.
RSpec.describe "Combobox client-side filtering (reactive_filter)", type: :system do
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

  it "narrows the preloaded options as you type — zero round trips" do
    visit "/filter_combobox"
    expect(page).to have_css("[role=option]", count: 5) # the whole catalog preloads
    install_fetch_spy

    query = find("[data-testid='filter-query']")
    query.send_keys("veg") # haystack match — no label says "veg"

    expect(page).to have_css("[data-testid='option-carrot']")
    expect(page).to have_css("[data-testid='option-kale']")
    expect(page).to have_css("[data-testid='option-apple']", visible: :hidden)
    expect(page).to have_css("[role=option]", count: 2)

    # Clearing restores every option — still client-side. (set("") drives
    # Playwright's fill, which fires a real input event — send_keys select-all
    # is platform-dependent.)
    query.set("")
    expect(page).to have_css("[role=option]", count: 5)

    # Not a single POST across the whole type, and no full-page reload.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "collapses an all-hidden group and reveals the empty node at 0 matches" do
    visit "/filter_combobox"
    expect(page).to have_css("[role=option]", count: 5)
    install_fetch_spy

    query = find("[data-testid='filter-query']")
    query.send_keys("kale")

    # Every fruit filtered out → the Fruits group header collapses with them.
    expect(page).to have_css("[data-testid='group-fruits']", visible: :hidden)
    expect(page).to have_css("[data-testid='group-vegetables']")
    expect(page).to have_css("[data-testid='filter-empty']", visible: :hidden)

    query.send_keys("zzz") # "kalezzz" — nothing matches
    expect(page).to have_css("[data-testid='filter-empty']", text: "No matches")
    expect(page).to have_css("[data-testid='group-vegetables']", visible: :hidden)

    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "composes with keyboard nav and a signed select — Arrow skips hidden options, Enter still round-trips" do
    visit "/filter_combobox"
    expect(page).to have_css("[role=option]", count: 5)
    install_fetch_spy

    query = find("[data-testid='filter-query']")
    query.send_keys("an") # matches Banana ("banana…") and Carrot ("…orange")
    expect(page).to have_css("[role=option]", count: 2)

    # Arrow Down highlights BANANA — Apple precedes it in the DOM but is
    # hidden, so the nav skips it (filter ∘ listnav). Zero POSTs so far.
    query.send_keys(:down)
    expect(page).to have_css("[data-testid='option-banana'][data-reactive-highlighted]")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)

    # Enter picks it — selection IS a signed reactive action (exactly one POST).
    query.send_keys(:enter)
    expect(page).to have_css("[data-testid='filter-combobox-selection']", text: "Selected: Banana")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
