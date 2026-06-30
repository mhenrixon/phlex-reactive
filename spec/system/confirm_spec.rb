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

  # Issue #55: setConfirmResolver lets an app swap the native window.confirm for
  # its own (possibly async) dialog — the seam that lets a reactive trigger reuse
  # Turbo.config.forms.confirm. We install an async resolver whose verdict is
  # driven by window.__confirmAnswer, so a Promise-returning dialog gates the
  # action exactly as the sync native prompt does — proving the gate is async
  # end-to-end in a real browser, under both Puma and Falcon.
  def install_async_resolver
    # A module script: import the vendored confirm seam and override it. The
    # resolver resolves on a later macrotask, so this also exercises the
    # "await an async dialog" path (not just a synchronously-resolved Promise).
    page.execute_script(<<~JS)
      window.__resolverInstalled = (async () => {
        const { setConfirmResolver } = await import("/vendor/confirm.js")
        setConfirmResolver((message) => new Promise((resolve) => {
          window.__confirmMessage = message
          setTimeout(() => resolve(window.__confirmAnswer === true), 10)
        }))
        window.__resolverReady = true
      })()
    JS
    # Block until the dynamic import + override has actually applied (the click
    # must wait for the seam — there's no DOM change to anchor a Capybara matcher).
    wait_for("confirm resolver never installed") { page.evaluate_script("window.__resolverReady === true") }
  end

  # Bounded poll on a JS condition Capybara can't express as a waiting matcher
  # (a window flag, not a DOM change). Raises `message` if it never holds.
  def wait_for(message = "condition never met", timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep(0.05)
    end
  end

  it "runs the action when a custom async resolver resolves true (#55)" do
    visit "/confirm"
    install_async_resolver
    page.execute_script("window.__confirmAnswer = true")
    expect(page).to have_css("[data-testid='runs']", text: "0")

    find("[data-testid='delete']").click

    expect(page).to have_css("[data-testid='runs']", text: "1")
    expect(page.evaluate_script("window.__confirmMessage")).to eq("Really delete this item?")
  end

  it "does NOT run the action when a custom async resolver resolves false (#55)" do
    visit "/confirm"
    install_async_resolver
    page.execute_script("window.__confirmAnswer = false")
    page.execute_script("window.__noReload = 'alive'")
    # Clear the message so we can detect when THIS click's resolver actually ran —
    # `runs` is already 0, so asserting it without waiting would pass before the
    # async decline even settles (a false green). We must observe the decline.
    page.execute_script("window.__confirmMessage = null")
    expect(page).to have_css("[data-testid='runs']", text: "0")

    find("[data-testid='delete']").click

    # Barrier: wait until the async resolver has actually run (it sets
    # __confirmMessage when invoked, then resolves false 10ms later). Only after
    # the decline has SETTLED do we assert nothing happened — so this can't pass
    # before the false resolution had its chance to (wrongly) enqueue a round trip.
    wait_for { page.evaluate_script("window.__confirmMessage") == "Really delete this item?" }

    # The decline settled. runs must still be 0 and the page must not have
    # navigated (the async decline still preventDefaulted up front).
    expect(page).to have_css("[data-testid='runs']", text: "0")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
