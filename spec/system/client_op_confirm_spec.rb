# frozen_string_literal: true

require "system_helper"

# Issue #178: confirm: on on_client(...). A zero-round-trip client op that is
# still destructive-feeling (clearing a draft) is gated behind the SAME
# overridable confirmResolver that on(:action, confirm:) uses (#52/#55). The
# client's runOps prompts BEFORE applying the ops: declining leaves the marker
# untouched (the op never ran) and never navigates; accepting runs the op. No
# token, no POST, ever — a fetch spy would see nothing on either path.
#
# We override window.confirm / install a custom resolver in the page so
# accept/decline is deterministic across both drivers and both servers
# (Puma + Falcon) — the client-op gate is what's under test, not the browser's
# native dialog chrome.
RSpec.describe "Confirmation-gated client op (issue #178)", type: :system do
  it "does NOT run the client op when the confirm is declined" do
    visit "/client_op_confirm"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")

    # window.confirm returns false → runOps must bail before applying the ops.
    page.execute_script("window.confirm = () => false")
    find("[data-testid='clear']").click

    # Give the (non-)op time to NOT happen, then assert the draft is untouched.
    # The marker proves the cancel didn't trigger a navigation either.
    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "runs the client op when the confirm is accepted" do
    visit "/client_op_confirm"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")

    # window.confirm returns true → the op fires and the draft text is cleared.
    page.execute_script("window.confirm = () => true")
    find("[data-testid='clear']").click

    expect(page).to have_css("[data-testid='draft']", text: "")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  # Issue #55 seam, now reused on the client-op path (#178): setConfirmResolver
  # swaps the native prompt for an app's (possibly async) themed dialog. The
  # SAME resolver gates both on(...) and on_client(...) — one themed dialog,
  # both paths. Proven async end-to-end in a real browser, under both servers.
  def install_async_resolver
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
    wait_for("confirm resolver never installed") { page.evaluate_script("window.__resolverReady === true") }
  end

  # Bounded poll on a JS condition Capybara can't express as a waiting matcher.
  def wait_for(message = "condition never met", timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep(0.05)
    end
  end

  it "runs the client op when a custom async resolver resolves true (#55 seam on #178)" do
    visit "/client_op_confirm"
    install_async_resolver
    page.execute_script("window.__confirmAnswer = true")
    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")

    find("[data-testid='clear']").click

    expect(page).to have_css("[data-testid='draft']", text: "")
    expect(page.evaluate_script("window.__confirmMessage")).to eq("Discard this draft?")
  end

  it "does NOT run the client op when a custom async resolver resolves false" do
    visit "/client_op_confirm"
    install_async_resolver
    page.execute_script("window.__confirmAnswer = false")
    page.execute_script("window.__noReload = 'alive'")
    # Clear the message so we can detect when THIS click's resolver actually ran —
    # the draft is already "unsaved draft", so asserting it without waiting would
    # pass before the async decline even settles (a false green). Observe the decline.
    page.execute_script("window.__confirmMessage = null")
    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")

    find("[data-testid='clear']").click

    # Barrier: wait until the async resolver has actually run (it sets
    # __confirmMessage when invoked, then resolves false 10ms later). Only after
    # the decline SETTLED do we assert nothing happened — so this can't pass before
    # the false resolution had its chance to (wrongly) apply the op.
    wait_for { page.evaluate_script("window.__confirmMessage") == "Discard this draft?" }

    expect(page).to have_css("[data-testid='draft']", text: "unsaved draft")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
