# frozen_string_literal: true

require "system_helper"

# Issue #179: CONDITIONAL confirm — confirm: as a Hash warns only when the field
# values look suspect, evaluated client-side over the collected fields (the same
# snapshot reactive_compute reads). Two forms:
#   * declarative { when: { total: 0 }, message: } — the reactive_show conditions
#     language; prompts when it MATCHES, submits silently otherwise.
#   * named { predicate: "end_before_start", message: } — a registered JS fn for
#     multi-field logic the single-field form can't express.
#
# We override window.confirm in the page so accept/decline is deterministic across
# both drivers and both servers (Puma + Falcon). The gate fires on the REAL signed
# action, so this proves the soft-validation dialog sits IN FRONT of the round trip
# — never in place of the server's authorize/default-deny.
RSpec.describe "Conditional confirm (issue #179)", type: :system do
  describe "declarative — warn only when total is 0" do
    it "prompts and blocks when total is 0 and the user declines" do
      visit "/conditional_confirm"
      expect(page).to have_css("[data-testid='runs']", text: "0")

      page.execute_script("window.confirm = () => false") # decline
      # total defaults to "0" → suspect → the dialog must fire.
      find("[data-testid='save']").click

      expect(page).to have_css("[data-testid='runs']", text: "0") # declined → never ran
    end

    it "prompts and runs when total is 0 and the user accepts" do
      visit "/conditional_confirm"
      page.execute_script("window.confirm = () => true") # accept

      find("[data-testid='save']").click

      expect(page).to have_css("[data-testid='runs']", text: "1") # accepted → ran
    end

    it "submits WITHOUT a dialog when total is non-zero (clean values)" do
      visit "/conditional_confirm"
      # A confirm stub that FAILS the test if it ever fires — a clean value must
      # not prompt at all.
      page.execute_script("window.confirm = () => { window.__prompted = true; return false }")
      fill_in_total("42")

      find("[data-testid='save']").click

      # Clean → no dialog, the action runs straight through.
      expect(page).to have_css("[data-testid='runs']", text: "1")
      expect(page.evaluate_script("window.__prompted === true")).to be(false)
    end

    # total is an <input value="0"> — set it via the DOM (no reactive_field here,
    # the name= binding is enough for both the POST and the client field collect).
    def fill_in_total(value)
      page.execute_script(<<~JS)
        const el = document.querySelector("[data-testid='total']")
        el.value = #{value.to_json}
        el.dispatchEvent(new Event("input", { bubbles: true }))
      JS
    end
  end

  describe "named predicate — warn only when end precedes start" do
    it "prompts and blocks when the range is inverted and the user declines" do
      visit "/schedule_confirm"
      expect(page).to have_css("[data-testid='runs']", text: "0")

      # Invert the range: end (2026-07-01) before start (2026-07-10) → predicate true.
      set_dates(starts: "2026-07-10", ends: "2026-07-01")
      page.execute_script("window.confirm = () => false")

      find("[data-testid='save']").click

      expect(page).to have_css("[data-testid='runs']", text: "0") # declined → never ran
    end

    it "submits WITHOUT a dialog when the range is valid (end after start)" do
      visit "/schedule_confirm"
      # Defaults are a valid range (start 07-01, end 07-10) → predicate false → no dialog.
      page.execute_script("window.confirm = () => { window.__prompted = true; return false }")

      find("[data-testid='save']").click

      expect(page).to have_css("[data-testid='runs']", text: "1")
      expect(page.evaluate_script("window.__prompted === true")).to be(false)
    end

    def set_dates(starts:, ends:)
      page.execute_script(<<~JS)
        const s = document.querySelector("[data-testid='starts-at']")
        const e = document.querySelector("[data-testid='ends-at']")
        s.value = #{starts.to_json}; s.dispatchEvent(new Event("input", { bubbles: true }))
        e.value = #{ends.to_json}; e.dispatchEvent(new Event("input", { bubbles: true }))
      JS
    end
  end
end
