# frozen_string_literal: true

require "system_helper"

# Issue #17: on(:action, event: "input", debounce: ms) coalesces rapid input
# events into ONE round trip after the quiet period, instead of one POST per
# keystroke. A blur flushes a pending dispatch so the last edit is never lost.
RSpec.describe "Debounced reactive input (issue #17)", type: :system do
  it "coalesces a burst of rapid input into a single action run" do
    visit "/debounce"
    page.execute_script("window.__noReload = 'alive'")
    expect(page).to have_css("[data-testid='runs']", text: "0")

    # Fire a burst of input events faster than the 150ms debounce window. If the
    # debounce works, exactly ONE search runs (runs -> 1); without it, each input
    # would POST (runs -> 5).
    page.execute_script(<<~JS)
      const field = document.querySelector("[data-testid='query']")
      const values = ["c", "ca", "cat", "cats", "catsx"]
      values.forEach((v, i) => {
        setTimeout(() => {
          field.value = v
          field.dispatchEvent(new Event("input", { bubbles: true }))
        }, i * 20)
      })
    JS

    # After the burst + quiet period, the single coalesced run lands.
    expect(page).to have_css("[data-testid='echo']", text: "catsx")
    expect(page).to have_css("[data-testid='runs']", text: "1")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "flushes the pending dispatch on blur" do
    visit "/debounce"
    expect(page).to have_css("[data-testid='runs']", text: "0")

    # One input then an immediate blur (before the 150ms window). The blur must
    # flush the pending dispatch rather than dropping the edit.
    page.execute_script(<<~JS)
      const field = document.querySelector("[data-testid='query']")
      field.value = "flushed"
      field.dispatchEvent(new Event("input", { bubbles: true }))
      field.dispatchEvent(new Event("blur"))
    JS

    expect(page).to have_css("[data-testid='echo']", text: "flushed")
    expect(page).to have_css("[data-testid='runs']", text: "1")
  end
end
