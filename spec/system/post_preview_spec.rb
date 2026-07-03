# frozen_string_literal: true

require "system_helper"

# End-to-end proof of reactive_text + typed compute inputs (issue #104):
#
#   * Typing in the title field updates a live PREVIEW HEADING (an identity
#     mirror — reactive_text(:title), no reducer output) and a CHARACTER COUNTER
#     (a reducer output written to a text node) IN-BROWSER, with NO round trip.
#   * The typed :string input reaches the reducer RAW, so the counter reflects the
#     character length — never a Number coercion of the text.
#   * A save fires the reactive action; the server persists and re-renders,
#     re-seeding the same derived heading + counter (the morph reconciles).
#
# One contract (reactive_text / typed compute), two execution sites — the client
# reducer for the instant feel, the server for the authoritative reconcile.
RSpec.describe "Post preview (reactive_text + typed compute, issue #104)", type: :system do
  let(:todo) { Todo.create!(title: "Draft") }

  it "mirrors the title into a heading + char counter in-browser with NO round trip" do
    visit "/post_preview/#{todo.id}"
    expect(page).to have_field("title", with: "Draft")
    expect(page).to have_css("[data-testid='preview']", text: "Draft")
    expect(page).to have_css("[data-testid='counter']", text: "5/80") # "Draft" = 5 chars

    # Count reactive action POSTs: the client-side mirror/compute must fire ZERO.
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS

    # Type a new title. The identity mirror repaints the heading; the reducer
    # repaints the counter — both on `input`, both client-side.
    fill_in "title", with: "Hello world"

    expect(page).to have_css("[data-testid='preview']", text: "Hello world") # live heading
    expect(page).to have_css("[data-testid='counter']", text: "11/80")       # raw string length
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)            # NO round trip
    expect(page.evaluate_script("window.__noReload")).to eq("alive")         # no reload

    # A digit-only title proves the :string input is read RAW, not through Number:
    # a numeric coercion would still count chars, but "007" as a Number is 7 — the
    # heading mirror is the tell (it shows the literal text, not a coerced value).
    fill_in "title", with: "007"
    expect(page).to have_css("[data-testid='preview']", text: "007") # literal, not "7"
    expect(page).to have_css("[data-testid='counter']", text: "3/80")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
  end

  it "reconciles through the server on save (the morph re-seeds the derived text)" do
    visit "/post_preview/#{todo.id}"
    page.execute_script("window.__noReload = 'alive'")

    fill_in "title", with: "Persisted title"
    expect(page).to have_css("[data-testid='counter']", text: "15/80") # client-computed first
    # The server-only echo still shows the OLD persisted value pre-save (the client
    # never touches it) — proof the barrier below is genuinely server-gated.
    expect(page).to have_css("[data-testid='saved']", text: "Draft")

    click_on "Save"

    # The barrier: the server-only echo flips to the persisted value ONLY after the
    # save round trip re-renders — so this waits for the actual reconcile, not the
    # client mirror. Then the seeded heading + counter reconcile without a reload.
    expect(page).to have_css("[data-testid='saved']", text: "Persisted title")
    expect(page).to have_css("[data-testid='preview']", text: "Persisted title")
    expect(page).to have_css("[data-testid='counter']", text: "15/80")
    expect(page).to have_field("title", with: "Persisted title")
    expect(page.evaluate_script("window.__noReload")).to eq("alive") # no full reload

    expect(todo.reload.title).to eq("Persisted title")
  end
end
