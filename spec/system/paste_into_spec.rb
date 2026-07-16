# frozen_string_literal: true

require "system_helper"

# Issue #228: the clipboard-source trigger, end to end. The OTP flagship's
# "Paste code" button is authored `hidden`; the connect gate reveals it where
# the Async Clipboard API exists. Clicking it reads the clipboard and feeds
# the field through the NORMAL input pipeline — the otp reducer normalizes
# (strips non-digits, caps at 6) and, when complete, auto-commits via
# $ops: ops.submit(), exactly as if the user had typed. A denied read is a
# silent no-op: the page must stay fully alive.
RSpec.describe "Clipboard paste trigger (issue #228 paste_into)", type: :system do
  def grant_clipboard
    page.driver.with_playwright_page do
      it.context.grant_permissions(%w[clipboard-read clipboard-write])
    end
  end

  def deny_clipboard
    page.driver.with_playwright_page { it.context.clear_permissions }
  end

  # Playwright's evaluate awaits the returned promise — execute_script would
  # fire-and-forget the async writeText.
  def write_clipboard(text)
    page.driver.with_playwright_page do
      it.evaluate("text => navigator.clipboard.writeText(text)", arg: text)
    end
  end

  def install_post_counter
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__marker = "kept"
    JS
  end

  it "reveals the authored-hidden trigger on connect (the clipboard API exists here)" do
    visit "/verification"

    # The waiting matcher IS the barrier for the connect pass: the button was
    # rendered hidden and only the availability gate un-hides it.
    expect(page).to have_css("[data-testid='paste']", text: "Paste code", visible: :visible)
  end

  it "pastes dirty clipboard text through the reducer and auto-commits ONE signed action" do
    visit "/verification"
    expect(page).to have_css("[data-testid='status']", text: "waiting")
    grant_clipboard
    write_clipboard("987-654")
    install_post_counter

    find("[data-testid='paste']").click

    # The same pipeline as typing: reducer-normalized, rising edge, one POST.
    expect(page).to have_css("[data-testid='status']", text: "verified:987654")
    expect(page).to have_field("code", with: "987654")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
    # Intercepted, never navigated: window state survived, no nav-probe page.
    expect(page.evaluate_script("window.__marker")).to eq("kept")
    expect(page).to have_no_css("[data-testid='nav-probe']")
    # The post-verify replace re-rendered the trigger in its AUTHORED hidden
    # state — the fresh controller's connect gate must reveal it again, or the
    # paste affordance vanishes after first use.
    expect(page).to have_css("[data-testid='paste']", visible: :visible)
  end

  it "focuses the field after a PARTIAL paste so typing continues from the caret" do
    visit "/verification"
    grant_clipboard
    write_clipboard("12-3")
    install_post_counter

    find("[data-testid='paste']").click

    # Incomplete → normalized but NOT submitted, and the field holds focus.
    expect(page).to have_field("code", with: "123")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script(<<~JS)).to be(true)
      document.activeElement === document.querySelector("[data-testid='code']")
    JS

    # The user keeps typing where the paste left off — completing commits once.
    find("[data-testid='code']").send_keys("456")
    expect(page).to have_css("[data-testid='status']", text: "verified:123456")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
  end

  it "treats a denied clipboard read as a silent no-op — the page stays fully alive" do
    visit "/verification"
    deny_clipboard # the prompt auto-denies; readText rejects
    install_post_counter

    find("[data-testid='paste']").click

    # The rejection contributed NOTHING: field untouched, no spurious POST.
    expect(page).to have_field("code", with: "")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)

    # ...and the field still works normally afterwards.
    find("[data-testid='code']").set("111")
    expect(page).to have_field("code", with: "111")
    expect(page).to have_css("[data-testid='status']", text: "waiting")
  end

  it "keeps the trigger hidden where the clipboard API is missing — a dead button never paints" do
    # Strip the API BEFORE the app JS runs (an insecure-context / webview
    # stand-in): the init script applies to the next navigation.
    visit "/verification"
    page.driver.with_playwright_page do
      it.add_init_script(script: <<~JS)
        Object.defineProperty(Navigator.prototype, "clipboard", { get: () => undefined })
      JS
    end
    visit "/verification"

    # The page is fully interactive (typing works)…
    find("[data-testid='code']").set("42")
    expect(page).to have_field("code", with: "42")
    # …but the authored-hidden trigger was never revealed.
    expect(page).to have_css("[data-testid='paste']", visible: :hidden)
    expect(page).to have_no_css("[data-testid='paste']", visible: :visible)
  end
end
