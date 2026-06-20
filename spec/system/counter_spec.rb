# frozen_string_literal: true

require "system_helper"

RSpec.describe "Counter (state-backed reactive component)", type: :system do
  it "increments, decrements, and resets without a full page reload" do
    visit "/counter"
    expect(page).to have_css("[data-testid='count']", text: "0")

    # Marker proves no full-page navigation happened during interactions.
    page.execute_script("window.__noReload = 'alive'")

    # Assert the count after each click so Capybara waits for the morph to land
    # before re-finding the (re-rendered) button.
    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: "1")

    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: "2")

    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: "3")

    find("[data-testid='dec']").click
    expect(page).to have_css("[data-testid='count']", text: "2")

    find("[data-testid='reset']").click
    expect(page).to have_css("[data-testid='count']", text: "0")

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "accumulates rapid clicks correctly (no in-flight token race)" do
    visit "/counter"
    expect(page).to have_css("[data-testid='count']", text: "0")

    # Fire five increments as fast as possible.
    page.execute_script(<<~JS)
      const btn = document.querySelector("[data-testid='inc']")
      for (let i = 0; i < 5; i++) btn.click()
    JS

    expect(page).to have_css("[data-testid='count']", text: "5")
  end
end
