# frozen_string_literal: true

require "system_helper"

# Declarative pending states (issue #181 — busy:): on(:save, busy: "Saving…")
# disables the trigger and swaps its innerHTML the instant the request is
# enqueued, and busy_on(:save) toggles data-reactive-busy on a spinner only while
# `save` is in flight. The save action sleeps 0.4s server-side so the busy state
# is observable BEFORE the morph reconciles — and so a rapid second click lands
# inside the pending window, where the disabled button swallows it (the disable
# IS the dedup; the queue only serializes tokens, it does not dedupe).
#
# The Save button is a COMPOSITE trigger (icon + label), so this also proves the
# text swap uses innerHTML, not textContent: the icon survives "Saving…" and is
# restored intact on settle (issue #181).
#
# Runs under Puma (sync) AND Falcon (async) in CI's server matrix.
RSpec.describe "Declarative pending states (issue #181 — busy:)", type: :system do
  it "swaps text, disables the button, and shows the busy spinner while pending" do
    visit "/loading_button"
    page.execute_script("window.__noReload = 'alive'")

    expect(page).to have_css("[data-testid='count']", text: "0")
    expect(page).to have_button("Save")
    # The composite trigger's icon is present at rest.
    expect(page).to have_css("[data-testid='save-icon']")
    # The spinner has no busy attribute at rest (styled hidden with pure CSS).
    expect(page).to have_no_css("[data-testid='spinner'][data-reactive-busy]")

    find("[data-testid='save']").click

    # Busy state paints IMMEDIATELY (at enqueue), BEFORE the 0.4s morph lands:
    #   * the button label swaps to "Saving…" and the button is disabled,
    #   * the busy_on spinner carries data-reactive-busy="save",
    #   * the root carries aria-busy + data-reactive-busy for the pending window.
    # A hint that never fired can't pass these no-wait assertions' waiting form.
    expect(page).to have_button("Saving…", disabled: true)
    expect(page).to have_css("[data-testid='spinner'][data-reactive-busy='save']")
    expect(page).to have_css("#loading-button[aria-busy='true']")
    expect(page).to have_css("#loading-button[data-reactive-busy~='save']")
    # The morph has NOT landed yet — the count is still 0.
    expect(page).to have_css("[data-testid='count']", text: "0")

    # …then the round trip settles: count becomes 1, the button restores to
    # "Save" and re-enables, and every busy marker clears.
    expect(page).to have_css("[data-testid='count']", text: "1")
    expect(page).to have_button("Save", disabled: false)
    # The icon SURVIVED the innerHTML swap-and-restore — textContent would have
    # destroyed it and never brought it back (issue #181).
    expect(page).to have_css("[data-testid='save-icon']")
    expect(page).to have_no_css("[data-testid='spinner'][data-reactive-busy]")
    expect(page).to have_no_css("#loading-button[aria-busy]")
    expect(page).to have_no_css("#loading-button[data-reactive-busy]")

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "dedupes a rapid double-click to exactly ONE server-side increment" do
    visit "/loading_button"
    expect(page).to have_css("[data-testid='count']", text: "0")

    # Two clicks as fast as possible. The first enqueues the POST and DISABLES the
    # button (busy: disables it) before the second click can register — a disabled
    # button fires no click event — so the second click is swallowed and only one
    # save runs.
    page.execute_script(<<~JS)
      const btn = document.querySelector("[data-testid='save']")
      btn.click()
      btn.click()
    JS

    # Exactly one increment landed. If the disable-at-enqueue dedup had failed,
    # two POSTs would serialize and the count would reach 2.
    expect(page).to have_css("[data-testid='count']", text: "1")
    expect(page).to have_button("Save", disabled: false)

    # A THIRD click after the settle still works (the button re-enabled) — the
    # dedup is per pending-window, not a permanent lock.
    find("[data-testid='save']").click
    expect(page).to have_css("[data-testid='count']", text: "2")
  end
end
