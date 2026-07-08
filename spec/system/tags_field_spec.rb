# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of the tag-chip input (issue #203):
#
#   * Everything is CLIENT-SIDE form state — the fetch spy proves ZERO action
#     POSTs across typing, adding (Enter free text, option click, listnav
#     Enter-pick), and removing; the hidden comma-joined field is the single
#     source of truth.
#   * Enter in the query input NEVER submits the enclosing form (the client
#     preventDefaults) — the window marker survives.
#   * A REAL form submit carries the hidden value to the server, which echoes
#     it back and re-renders the chips (the server-side half of the loop).
#
# One generic controller, no per-widget JavaScript — the wiring is
# reactive_tags + reactive_filter on the root, reactive_listnav +
# reactive_tags_add on the input, reactive_tags_option on each suggestion.
RSpec.describe "Tag-chip input (reactive_tags)", type: :system do
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

  def hidden_value
    find("[data-testid='tags-value']", visible: :hidden).value
  end

  it "adds free text on Enter, dedupes, and never POSTs or submits the form" do
    visit "/tags_field"
    expect(page).to have_css("[data-testid='tags-query']")
    install_fetch_spy

    query = find("[data-testid='tags-query']")
    query.send_keys("Elixir", :enter)

    expect(page).to have_css("[data-testid='tag-chip']", text: "Elixir")
    expect(hidden_value).to eq("Elixir")
    expect(query.value).to eq("") # cleared for the next tag

    # A case-insensitive duplicate adds nothing and keeps the text for correction.
    query.send_keys("ELIXIR", :enter)
    expect(page).to have_field("tag_query", with: "ELIXIR")
    expect(page).to have_css("[data-testid='tag-chip']", count: 1)
    expect(hidden_value).to eq("Elixir")

    # No POST, and Enter never submitted the GET form (no navigation).
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "narrows suggestions as you type; click and listnav Enter both add the option" do
    visit "/tags_field"
    expect(page).to have_css("[role=option]", count: 5)
    install_fetch_spy

    query = find("[data-testid='tags-query']")
    query.send_keys("db") # haystack match — the Postgres label never says "db"
    expect(page).to have_css("[role=option]", count: 1)

    # Click-to-add: chip appears, option hides (selected), query resets to full list.
    find("[data-testid='option-postgres']").click
    expect(page).to have_css("[data-testid='tag-chip']", text: "Postgres")
    expect(hidden_value).to eq("Postgres")
    expect(page).to have_css("[data-testid='option-postgres']", visible: :hidden)
    expect(page).to have_css("[role=option]", count: 4) # cleared query, minus the selected

    # Keyboard path: type, Arrow to highlight, Enter picks the HIGHLIGHTED
    # option (not the typed fragment).
    query.send_keys("frontend")
    expect(page).to have_css("[role=option]", count: 2)
    query.send_keys(:down)
    expect(page).to have_css("[data-testid='option-hotwire'][data-reactive-highlighted]")
    query.send_keys(:enter)

    expect(page).to have_css("[data-testid='tag-chip']", text: "Hotwire")
    expect(hidden_value).to eq("Postgres,Hotwire")
    expect(page).to have_css("[data-testid='tag-chip']", count: 2)

    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "removes a chip, resurfaces its suggestion, and survives a clear-query re-filter" do
    visit "/tags_field?tags=Ruby,Rails"
    expect(page).to have_css("[data-testid='tag-chip']", count: 2)
    expect(page).to have_css("[data-testid='option-ruby']", visible: :hidden) # selected on load
    install_fetch_spy

    within("[data-reactive-tag='Ruby']") { click_button "×" }

    expect(page).to have_css("[data-testid='tag-chip']", count: 1)
    expect(hidden_value).to eq("Rails")
    expect(page).to have_css("[data-testid='option-ruby']") # resurfaced

    # Typing then clearing re-filters everything visible — EXCEPT the still-
    # selected Rails (the syncFilter selected-guard).
    query = find("[data-testid='tags-query']")
    query.send_keys("x")
    query.set("")
    expect(page).to have_css("[role=option]", count: 4)
    expect(page).to have_css("[data-testid='option-rails']", visible: :hidden)

    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "a real form submit carries the comma-joined value to the server" do
    visit "/tags_field"
    expect(page).to have_css("[data-testid='tags-query']")

    query = find("[data-testid='tags-query']")
    query.send_keys("Ruby", :enter)
    expect(page).to have_css("[data-testid='tag-chip']", text: "Ruby")
    query.send_keys("Elixir", :enter)
    expect(page).to have_css("[data-testid='tag-chip']", text: "Elixir")

    find("[data-testid='tags-submit']").click

    # The server received the hidden field, echoed it, and re-rendered the
    # chips server-side (the first-paint path).
    expect(page).to have_css("[data-testid='tags-submitted']", text: "Saved: Ruby,Elixir")
    expect(page).to have_css("[data-testid='tag-chip']", count: 2)
    expect(hidden_value).to eq("Ruby,Elixir")
  end
end
