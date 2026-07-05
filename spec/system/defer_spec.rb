# frozen_string_literal: true

require "system_helper"

# Deferred reply segments in a real browser (issue #165): the cheap companion
# paints IMMEDIATELY while the expensive rollup is pending (keep-content
# default: stale value + data-reactive-defer-pending), the real render streams
# in without a reload, rapid actions supersede (no stale paint), and the
# skeleton variant swaps the placeholder in. Waiting matchers are the barrier
# for every async hop — never a snapshot right after a click.
RSpec.describe "Deferred reply segments (issue #165)", type: :system do
  around do |example|
    SlowTotalsComponent.render_delay_ms = 300
    example.run
  ensure
    SlowTotalsComponent.render_delay_ms = 0
  end

  it "paints the cheap stream immediately, marks the totals pending, then streams the real render in" do
    visit "/defer"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='totals-value']", text: "0")

    find("[data-testid='defer-bump']").click

    # The cheap companion lands from the reply WHILE the totals are still
    # pending — this is the perceived-performance contract in one assertion:
    # count is fresh, totals still show the STALE value, marked pending.
    expect(page).to have_css("[data-testid='defer-count']", text: "1")
    expect(page).to have_css("#slow-totals[data-reactive-defer-pending]")
    expect(page).to have_css("[data-testid='totals-value']", text: "0")

    # The deferred render arrives: fresh value, pending marker gone, no reload.
    expect(page).to have_css("[data-testid='totals-value']", text: "2")
    expect(page).to have_no_css("#slow-totals[data-reactive-defer-pending]")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "rapid actions supersede — the totals settle on the LAST value and never regress" do
    visit "/defer"
    expect(page).to have_css("[data-testid='totals-value']", text: "0")

    # Two clicks faster than the 300ms render: the first defer is superseded.
    find("[data-testid='defer-bump']").click
    expect(page).to have_css("[data-testid='defer-count']", text: "1") # reply 1 applied
    find("[data-testid='defer-bump']").click
    expect(page).to have_css("[data-testid='defer-count']", text: "2")

    expect(page).to have_css("[data-testid='totals-value']", text: "4")

    # The superseded first render (value 2) must never paint AFTER the fresh
    # one — hold the assertion across a full render-delay window.
    sleep 0.6
    expect(page).to have_css("[data-testid='totals-value']", text: "4")
  end

  it "placeholder: true swaps the skeleton in immediately, then the real render replaces it" do
    visit "/defer"
    expect(page).to have_css("[data-testid='totals-value']", text: "0")

    find("[data-testid='defer-bump-skeleton']").click

    # The shimmer shell replaces the totals synchronously with the reply…
    expect(page).to have_css("[data-testid='totals-shimmer']")
    # …and the deferred render replaces the shell.
    expect(page).to have_css("[data-testid='totals-value']", text: "2")
    expect(page).to have_no_css("[data-testid='totals-shimmer']")
  end

  it "the deferred component arrives INTERACTIVE (fresh token on the streamed root)" do
    visit "/defer"
    find("[data-testid='defer-bump']").click
    expect(page).to have_css("[data-testid='totals-value']", text: "2")

    token = page.evaluate_script(
      %(document.getElementById("slow-totals").getAttribute("data-reactive-token-value")),
    )
    expect(token).to be_a(String)
    expect(token.length).to be > 20
  end
end
