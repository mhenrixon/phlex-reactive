# frozen_string_literal: true

require 'system_helper'

# The docs-owned latency toggle (issue #149 step 2). The loading-states page ships
# a FAST server action (LoadingButtonComponent#save has no sleep), so the busy
# window is unobservable on localhost. Flipping the toggle injects a client-side
# delay via the gem's enableLatencySim, making busy: + busy_on observable.
RSpec.describe 'Latency toggle', type: :system do
  it 'makes the busy: label + busy spinner observable when the sim is on' do
    visit '/docs/example-loading-states'

    # Baseline: the button reads "Save" and is enabled.
    expect(page).to have_css("[data-testid='save']", text: 'Save')

    # Flip the simulator on (500 ms delay, per the page).
    find("[data-testid='latency-toggle-input']").click

    # Click Save: during the injected delay the button label swaps to "Saving…",
    # the button is disabled, and the scoped spinner carries data-reactive-busy.
    find("[data-testid='save']").click

    expect(page).to have_css("[data-testid='save'][disabled]", text: 'Saving…')
    expect(page).to have_css("[data-testid='spinner'][data-reactive-busy]")

    # After the round trip settles the button reverts and the count advanced once.
    expect(page).to have_css("[data-testid='save']:not([disabled])", text: 'Save')
    expect(page).to have_css("[data-testid='saved-count']", text: 'Saved 1 times')
  end

  it 'dedups a rapid double-click to a single POST (the disable IS the dedup)' do
    visit '/docs/example-loading-states'
    expect(page).to have_css("[data-testid='saved-count']", text: 'Saved 0 times')

    # Fire two native clicks back-to-back via execute_script — Capybara's own
    # click auto-waits for the button to re-enable, which would defeat the test.
    # The first click enqueues the POST and disables the button (disable_with)
    # before the second lands, so a disabled button swallows the second click.
    page.execute_script(<<~JS)
      const btn = document.querySelector("[data-testid='save']")
      btn.click()
      btn.click()
    JS

    # Exactly one increment landed — the second click hit a dead control.
    expect(page).to have_css("[data-testid='saved-count']", text: 'Saved 1 times')
    expect(page).to have_no_css("[data-testid='saved-count']", text: 'Saved 2 times')

    # A THIRD click after the settle still works — the dedup is per pending
    # window, not a permanent lock.
    find("[data-testid='save']").click
    expect(page).to have_css("[data-testid='saved-count']", text: 'Saved 2 times')
  end

  it 'stays instant with the simulator off (no observable busy window)' do
    visit '/docs/example-loading-states'

    # No toggle: the fast action settles immediately; the count advances with no
    # lingering disabled/"Saving…" state to trip over.
    find("[data-testid='save']").click
    expect(page).to have_css("[data-testid='saved-count']", text: 'Saved 1 times')
    expect(page).to have_css("[data-testid='save']:not([disabled])", text: 'Save')
  end
end
