# frozen_string_literal: true

require "system_helper"

# Optimistic visual hints (issue #98): on(..., optimistic: { … }) applies a
# small, reversible, cosmetic vocabulary the instant the trigger fires — before
# the round trip — and reverts it if the action fails.
#
#   * checked: :keep — a click/change checkbox flips NATIVELY now (today the
#     unconditional preventDefault suppresses the flip until the morph), and a
#     companion toggle_class paints in the same gesture. The toggle action here
#     sleeps 0.4s server-side so the flip is observable BEFORE the morph.
#   * a failing action (undeclared :boom → default-deny 403) applies its
#     add_class hint, then REVERTS it when the failure lands.
#   * hide: true + reply.remove is the instant delete recipe: the row hides now,
#     the reply removes it — no flash-back.
#
# Runs under Puma (sync) AND Falcon (async) in CI's server matrix.
RSpec.describe "Optimistic visual hints (issue #98)", type: :system do
  it "flips a checkbox natively BEFORE the slow morph lands, then reconciles" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")

    expect(page).to have_css("[data-testid='opt-row'][data-done='false']")
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(false)

    find("[data-testid='opt-check']").click

    # Client-first: the native flip + toggle_class paint immediately, while the
    # server (sleeping 0.4s) has NOT yet morphed — data-done is still "false".
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(true)
    expect(page).to have_css("[data-testid='status'].is-done")
    expect(page).to have_css("[data-testid='opt-row'][data-done='false']") # morph not landed yet

    # …then the morph reconciles from server truth: data-done becomes "true".
    expect(page).to have_css("[data-testid='opt-row'][data-done='true']")
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(true)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "reverts the optimistic hint when the action fails (undeclared → 403)" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")

    boom = find("[data-testid='opt-boom']")
    expect(page).to have_no_css("[data-testid='opt-boom'].pending")

    boom.click

    # The hint was applied (add_class "pending"); when the 403 lands, the client
    # replays the inverse (remove_class "pending"). The waiting matcher is the
    # barrier for the async round trip + revert.
    expect(page).to have_no_css("[data-testid='opt-boom'].pending")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "hides the row instantly, then reply.remove drops it (no flash-back)" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='opt-row']")

    find("[data-testid='opt-destroy']").click

    # hide: true hid the row immediately (hidden), and reply.remove then removes
    # the node entirely — either way it's gone and never reappears.
    expect(page).to have_no_css("[data-testid='opt-row']", visible: :all)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
