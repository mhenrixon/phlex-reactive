# frozen_string_literal: true

require "system_helper"

# Issue #215: effects in a real browser, driven by the gem's REAL shipped CSS
# (the demo page inlines app/assets/stylesheets/phlex/reactive/effects.css).
# The contract under test: an exit-declared removal keeps the element in the
# DOM while its animation runs and only then removes it; an arriving row
# carries its enter class; an update flashes the fresh root and cleans the
# class up afterwards — all without a full page reload, on Puma AND Falcon.
RSpec.describe "Reactive effects (issue #215)", type: :system do
  it "animates exit before removal, enter on arrival, and update on re-render — no reload" do
    visit "/effects"
    expect(page).to have_css("#fx-row-1")

    page.execute_script("window.__noReload = 'alive'")

    # UPDATE: ping replaces the container; the fresh root flashes (declared
    # update: :highlight) and the transient class is cleaned up on animationend.
    find("[data-testid='fx-ping']").click
    expect(page).to have_css("[data-testid='fx-demo'].reactive-fx--highlight-update")
    expect(page).to have_no_css(".reactive-fx--highlight-update")

    # ENTER: the appended row arrives wearing its slide-enter class (declared on
    # the ROW class — the incoming template root carries the attr), then settles.
    find("[data-testid='fx-add']").click
    expect(page).to have_css("#fx-row-2.reactive-fx--slide-enter", text: "Row 2")
    expect(page).to have_no_css(".reactive-fx--slide-enter")

    # A second add proves the container's token rolled forward (reply.streams'
    # token-only refresh — the add-once-only regression, cosmos#1939).
    find("[data-testid='fx-add']").click
    expect(page).to have_css("#fx-row-3", text: "Row 3")

    # EXIT: dismissing a row animates it out FIRST — the element is still in
    # the DOM wearing the fade-exit class — and only then removes it.
    find("[data-testid='dismiss-1']").click
    expect(page).to have_css("#fx-row-1.reactive-fx--fade-exit")
    expect(page).to have_no_css("#fx-row-1")

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "per-call effect: false suppresses the row's declared exit (instant removal)" do
    visit "/effects"
    expect(page).to have_css("#fx-row-1")

    # dismiss_plain replies reply.remove(effect: false) — the wire carries
    # data-reactive-effect="off", so the declared fade-exit never runs. The row
    # must be gone WITHOUT ever wearing the exit class; Capybara's first poll
    # after the round trip would catch a 600ms animation reliably.
    find("[data-testid='dismiss-plain-1']").click
    expect(page).to have_no_css("#fx-row-1")
    expect(page).to have_no_css(".reactive-fx--fade-exit")
  end
end
