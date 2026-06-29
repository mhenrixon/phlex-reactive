# frozen_string_literal: true

require "system_helper"

# Issue #52: on(:action, confirm: "message") gates a reactive trigger behind a
# confirmation prompt. The reactive controller preempts the event (preventDefault
# + its own POST), so Hotwire's data-turbo-confirm can't run — `confirm:` threads
# a data-reactive-confirm-param and the client prompts window.confirm() BEFORE
# enqueuing. Declining must run NOTHING (the action never fires); accepting runs
# the action exactly as an unguarded trigger would.
#
# We override window.confirm in the page so accept/decline is deterministic
# across both drivers and both servers (Puma + Falcon) — the click path is what's
# under test, not the browser's native dialog chrome.
RSpec.describe "Confirmation-gated reactive action (issue #52)", type: :system do
  it "does NOT run the action when the confirm is declined" do
    visit "/confirm"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='runs']", text: "0")

    # window.confirm returns false → the dispatch must bail before any POST.
    page.execute_script("window.confirm = () => false")
    find("[data-testid='delete']").click

    # Give the (non-)round-trip time to NOT happen, then assert runs is still 0.
    # The marker proves the cancel didn't trigger a navigation either.
    expect(page).to have_css("[data-testid='runs']", text: "0")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "runs the action when the confirm is accepted" do
    visit "/confirm"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='runs']", text: "0")

    # window.confirm returns true → the action fires and runs increments.
    page.execute_script("window.confirm = () => true")
    find("[data-testid='delete']").click

    expect(page).to have_css("[data-testid='runs']", text: "1")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
