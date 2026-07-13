# frozen_string_literal: true

require "system_helper"

# Issue #226: the MULTI-BOX code entry, end to end — six single-character boxes
# behind one reducer. A paste into the FIRST box redistributes one digit per
# box; typing advances focus to the next box on every digit (the content-keyed
# $ops latch fires each DIFFERENT focus target); the sixth digit auto-commits
# exactly ONE signed action carrying the hidden joined `code` field.
RSpec.describe "Split code boxes (issue #226 multi-input $ops)", type: :system do
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

  it "redistributes a dirty paste across the boxes and auto-commits once" do
    visit "/split_code"
    expect(page).to have_css("[data-testid='status']", text: "waiting")
    install_post_counter

    # Paste-shaped input into the FIRST box: the reducer joins, strips, and
    # fans one digit out per box, completes, and submits.
    find("[data-testid='d1']").set("987-654")

    expect(page).to have_css("[data-testid='status']", text: "verified:987654")
    expect(page).to have_field("d1", with: "9")
    expect(page).to have_field("d6", with: "4")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
    expect(page.evaluate_script("window.__marker")).to eq("kept") # no navigation
    expect(page).to have_no_css("[data-testid='nav-probe']")
  end

  it "advances focus box by box while typing, then submits on the sixth digit" do
    visit "/split_code"
    install_post_counter

    # The hidden `code` field is written by the SAME reducer pass that fires
    # the focus op, so waiting on it is the async barrier for each advance.
    find("[data-testid='d1']").send_keys("1")
    expect(page).to have_field("code", with: "1", type: "hidden")
    expect(page.evaluate_script("document.activeElement?.name")).to eq("d2")

    find("[data-testid='d2']").send_keys("2")
    expect(page).to have_field("code", with: "12", type: "hidden")
    expect(page.evaluate_script("document.activeElement?.name")).to eq("d3")

    find("[data-testid='d3']").send_keys("3")
    find("[data-testid='d4']").send_keys("4")
    find("[data-testid='d5']").send_keys("5")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0) # still incomplete

    find("[data-testid='d6']").send_keys("6")

    expect(page).to have_css("[data-testid='status']", text: "verified:123456")
    expect(page.evaluate_script("window.__actionPosts")).to eq(1)
  end
end
