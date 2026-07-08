# frozen_string_literal: true

require "system_helper"

# End-to-end proof of the connect-time compute seed (issue #199).
#
# The component renders its two derived outputs (total, half) and its cross-root
# mirror (#seed-total-label) BLANK — an app that relies on the client to compute
# the first paint. Before #199, those nodes stayed blank until the first user
# edit, and a synthetic seed `input` under-applied (only the FIRST output
# painted). Now connect() runs ONE full recompute, so on a FRESH page load —
# with no user interaction and no round trip — every output AND the mirror paint
# from a single reducer result.
RSpec.describe "Connect-time compute seed (issue #199)", type: :system do
  it "self-seeds ALL derived outputs + the mirror on a fresh render, no round trip" do
    # Spy the reactive endpoint BEFORE anything can post — the seed is client-only.
    visit "/compute_seed"
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS

    # The seed inputs were rendered; the derived fields + mirror seed on CONNECT.
    expect(page).to have_field("a", with: "2")
    expect(page).to have_field("b", with: "4")

    # Both outputs painted from the ONE connect-time pass — the early one (total)
    # AND the later one (half), the exact pair the issue reported under-applying.
    expect(page).to have_field("total", with: "6")
    expect(page).to have_field("half", with: "3")

    # The cross-root mirror painted too — it seeded "—", so "6" PROVES the paint
    # happened (the text had to change, not coincide).
    expect(page).to have_css("#seed-total-label", text: "6")

    # It was entirely client-side: no reactive action POST, no full reload.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "recomputes on a later user edit too (the seed does not disable live compute)" do
    visit "/compute_seed"
    expect(page).to have_field("total", with: "6") # seeded

    # A real edit still drives the client reducer — the seed is additive, not a
    # one-shot that swallows subsequent input.
    fill_in "a", with: "10"

    expect(page).to have_field("total", with: "14") # 10 + 4
    expect(page).to have_field("half", with: "7")
    expect(page).to have_css("#seed-total-label", text: "14")
  end
end
