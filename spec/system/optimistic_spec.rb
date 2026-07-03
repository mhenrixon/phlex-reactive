# frozen_string_literal: true

require "system_helper"

# Optimistic visual hints (issue #98): on(..., optimistic: { … }) applies a
# small, reversible, cosmetic vocabulary the instant the trigger fires — before
# the round trip — and reverts it if the action fails.
#
#   * checked: :keep on a CLICK-bound checkbox flips NATIVELY now — the client
#     skips the unconditional preventDefault that today suppresses the flip until
#     the morph — and a companion toggle_class paints in the same gesture.
#   * checked: :keep on a CHANGE-bound checkbox: the flip is already native
#     (change isn't cancelable), so :keep only contributes the failure revert.
#   * a failing action (:boom raises a registered authorization error → 403)
#     applies its add_class hint, then REVERTS it when the failure lands.
#   * hide: true + reply.remove is the instant delete recipe: the row hides now,
#     the reply removes it — no flash-back.
#
# The toggle action sleeps 0.4s server-side so the optimistic flip is observable
# BEFORE the morph reconciles it (client-first, not a race). Runs under Puma
# (sync) AND Falcon (async) in CI's server matrix.
RSpec.describe "Optimistic visual hints (issue #98)", type: :system do
  # The core #98 regression: a CLICK-bound checkbox. If the skip-preventDefault
  # branch broke, the client would preventDefault the click and the box would NOT
  # flip until the (0.4s-delayed) morph — so the "checked BEFORE the morph"
  # assertion below is exactly what guards it.
  it "flips a CLICK-bound checkbox natively BEFORE the slow morph, then reconciles" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")

    expect(page).to have_css("[data-testid='opt-row'][data-done='false']")
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(false)

    find("[data-testid='opt-check']").click

    # Client-first: the native flip + toggle_class paint immediately, while the
    # server (sleeping 0.4s) has NOT yet morphed — data-done is still "false".
    # This flip only happens because dispatch() skipped preventDefault on the
    # click-bound checkbox (the new #98 branch).
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(true)
    expect(page).to have_css("[data-testid='status'].is-done")
    expect(page).to have_css("[data-testid='opt-row'][data-done='false']") # morph not landed yet

    # …then the morph reconciles from server truth: data-done becomes "true".
    expect(page).to have_css("[data-testid='opt-row'][data-done='true']")
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check']\").checked")).to be(true)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  # A CHANGE-bound checkbox: preventDefault is already a no-op on `change`, so the
  # native flip happens regardless — :keep's job here is only the failure revert.
  # The flip is still observable before the delayed morph.
  it "keeps a CHANGE-bound checkbox flipped before the morph reconciles it" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")

    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check-change']\").checked")).to be(false)

    find("[data-testid='opt-check-change']").click

    # Flipped natively and NOT reverted by the round trip (it succeeds); still
    # ahead of the 0.4s morph.
    expect(page.evaluate_script("document.querySelector(\"[data-testid='opt-check-change']\").checked")).to be(true)
    expect(page).to have_css("[data-testid='opt-row'][data-done='true']") # morph reconciles
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "reverts the optimistic hint when the action fails (authorization → 403)" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")

    expect(page).to have_no_css("[data-testid='opt-boom'].pending")

    find("[data-testid='opt-boom']").click

    # The hint is applied IMMEDIATELY (add_class "pending" on the button itself);
    # the boom action sleeps 0.4s before it fails, so this state is observable and
    # a hint that never appeared can't pass this spec…
    expect(page).to have_css("[data-testid='opt-boom'].pending")
    # …then, when the 403 lands, the client replays the inverse (remove_class
    # "pending"). The waiting matcher is the barrier for the async round trip.
    expect(page).to have_no_css("[data-testid='opt-boom'].pending")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "hides the row instantly, then reply.remove drops it (no flash-back)" do
    visit "/optimistic"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='opt-row']")

    find("[data-testid='opt-destroy']").click

    # hide: true hid the row IMMEDIATELY — assert the hidden state with no wait so
    # this spec can't pass on a hint that never fired…
    expect(page).to have_css("[data-testid='opt-row']", visible: :hidden, wait: 0)
    # …then reply.remove removes the node entirely — it's gone and never reappears.
    expect(page).to have_no_css("[data-testid='opt-row']", visible: :all)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
