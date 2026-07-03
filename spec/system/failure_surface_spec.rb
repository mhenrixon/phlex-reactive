# frozen_string_literal: true

require "system_helper"

# The user-visible failure surface end-to-end (issue #100). A failing action now
# SHOWS the user a flash (instead of silently doing nothing): the endpoint
# renders an error_flash turbo-stream at the same status, the client applies it
# and marks the root data-reactive-error; the next success clears the mark; a
# dismiss_after flash removes itself. Runs under Puma AND Falcon (the reactive
# round trip must pass sync and async).
RSpec.describe "User-visible failure surface (issue #100)", type: :system do
  # error_flash is process-global config read at request time; the in-process
  # Capybara server thread sees it. Set it for this file only and restore after,
  # so no other suite is affected.
  before { Phlex::Reactive.error_flash = -> { "Action failed (#{it})" } }
  after { Phlex::Reactive.error_flash = nil }

  it "shows an error flash on a failing action and clears data-reactive-error on the next success" do
    visit "/failure_surface"
    expect(page).to have_css("[data-testid='boom']")

    page.execute_script('window.__noReload = "alive"')

    # A failing (undeclared) action → 403 with an error_flash turbo-stream.
    find("[data-testid='boom']").click

    # The flash the endpoint rendered is now VISIBLE in the host-app flash region
    # (the waiting matcher is the barrier for the async round trip), and the root
    # carries the failure marker.
    expect(page).to have_css("#flash", text: "Action failed (forbidden)")
    expect(page).to have_css("[data-reactive-error='http']#failure-surface")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    # A subsequent SUCCESSFUL action re-renders the root and clears the marker.
    find("[data-testid='succeed']").click
    expect(page).to have_css("[data-testid='count']", text: "1")
    expect(page).to have_no_css("[data-reactive-error]#failure-surface")
  end

  it "self-dismisses a dismiss_after flash after its timeout" do
    visit "/failure_surface"
    expect(page).to have_css("[data-testid='flash-now']")

    find("[data-testid='flash-now']").click

    # The flash appears...
    expect(page).to have_css("#flash", text: "gone soon")
    # ...then removes itself once the 300ms timeout elapses (a waiting matcher,
    # so no manual sleep — Capybara polls until the node is gone).
    expect(page).to have_no_css("#flash [data-reactive-dismiss-after]")
    expect(page).to have_no_text("gone soon")
  end
end
