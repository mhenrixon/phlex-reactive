# frozen_string_literal: true

require "system_helper"

# Issue #226: the $ops flagship, end to end — a one-time-code field whose
# reducer normalizes every input (strip non-digits, cap at 6) and, once
# complete, emits `$ops: ops.submit()`. requestSubmit fires a real submit event
# that on(:verify, event: "submit") intercepts into ONE signed action POST —
# no navigation (the form's action points at the nav-probe page), no bespoke
# controller. Rising-edge semantics are proven in the browser: a 7th keystroke
# (capped back to the same complete value) never re-fires; going incomplete
# re-arms; a fresh render with a complete value (the post-verify replace) never
# self-fires.
RSpec.describe "Verification code auto-commit (issue #226 $ops)", type: :system do
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

  it "normalizes dirty input and commits exactly ONE signed action when complete" do
    visit "/verification"
    expect(page).to have_css("[data-testid='status']", text: "waiting")
    install_post_counter

    # Paste-shaped dirty input: separators stripped, then complete → submit.
    find("[data-testid='code']").set("123-456")

    expect(page).to have_css("[data-testid='status']", text: "verified:123456")
    expect(page).to have_field("code", with: "123456") # reducer-normalized
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
    # Intercepted, never navigated: window state survived, no nav-probe page.
    expect(page.evaluate_script("window.__marker")).to eq("kept")
    expect(page).to have_no_css("[data-testid='nav-probe']")
  end

  it "never re-fires while complete and re-arms only after going incomplete" do
    visit "/verification"
    install_post_counter

    find("[data-testid='code']").set("111111")
    expect(page).to have_css("[data-testid='status']", text: "verified:111111")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)

    # The post-verify replace re-rendered the form with the COMPLETE value; the
    # fresh controller's seed pass arms without firing. Another digit (wherever
    # the caret lands) is capped straight back to 6 — the value stays complete,
    # so there is no rising edge and NO second commit.
    find("[data-testid='code']").send_keys("7")
    expect(find("[data-testid='code']").value.length).to eq(6)
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)

    # Going incomplete re-arms (and alone commits nothing)...
    find("[data-testid='code']").set("222")
    expect(page).to have_field("code", with: "222")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)

    # ...then completing again fires exactly one more commit.
    find("[data-testid='code']").set("222333")
    expect(page).to have_css("[data-testid='status']", text: "verified:222333")
    expect(page.evaluate_script("window.__actionPosts")).to eq(2)
  end
end
