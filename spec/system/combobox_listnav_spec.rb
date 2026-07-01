# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of client-side list navigation (issue #72):
#
#   * Arrow Up/Down move a highlight among the options IN-BROWSER — NO round trip.
#   * Enter picks the highlighted option by clicking its own on(:select) trigger,
#     so the SELECTION is a normal signed reactive action (server morphs it in).
#   * Escape clears the highlight (also client-side).
#
# One generic controller, no per-combobox JavaScript — the keyboard wiring rides
# on the search input via on(:search, …, listnav: "[role=option]").
RSpec.describe "Combobox keyboard navigation (client-side listnav)", type: :system do
  it "highlights options with the arrow keys, no server round trip" do
    # Seed the query so options render on load; the nav itself is what we test.
    visit "/combobox?q=a"
    query = find("[data-testid='combobox-query']")
    expect(page).to have_css("[data-testid='combobox-results'] [role=option]", minimum: 2)

    # Count reactive action POSTs from here on: arrow navigation must fire ZERO.
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS

    # Arrow Down highlights the first option (data-reactive-highlighted).
    query.send_keys(:down)
    expect(page).to have_css("[role=option][data-reactive-highlighted]", count: 1)
    first_highlighted = find("[role=option][data-reactive-highlighted]").text

    # Arrow Down again moves the highlight to the next option.
    query.send_keys(:down)
    expect(page).to have_css("[role=option][data-reactive-highlighted]", count: 1)
    expect(find("[role=option][data-reactive-highlighted]").text).not_to eq(first_highlighted)

    # Still exactly one highlighted, and NOT a single POST fired for the nav.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    # Escape clears the highlight — still client-side.
    query.send_keys(:escape)
    expect(page).to have_no_css("[role=option][data-reactive-highlighted]")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
  end

  it "picks the highlighted option on Enter (a signed reactive select)" do
    visit "/combobox?q=berr" # Blueberry, Cranberry
    query = find("[data-testid='combobox-query']")
    expect(page).to have_css("[data-testid='combobox-results'] [role=option]", minimum: 2)

    query.send_keys(:down)  # highlight the first match
    highlighted = find("[role=option][data-reactive-highlighted]").text

    query.send_keys(:enter) # pick it → fires on(:select) → server morphs

    # The selection landed (a real reactive round trip performed the select).
    expect(page).to have_css("[data-testid='combobox-selection']", text: "Selected: #{highlighted}")
    expect(page).to have_field("query", with: highlighted)
  end

  it "Enter with nothing highlighted does not select" do
    visit "/combobox?q=apple"
    query = find("[data-testid='combobox-query']")
    expect(page).to have_css("[role=option]", minimum: 1)

    # No arrow press → no highlight → Enter is a no-op for selection.
    query.send_keys(:enter)
    expect(page).to have_no_css("[data-testid='combobox-selection']")
  end
end
