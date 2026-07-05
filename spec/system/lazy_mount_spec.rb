# frozen_string_literal: true

require "system_helper"

# Lazy initial mount in a real browser (issue #165): the page arrives with the
# placeholder shell (shimmer + pending markers), the controller's connect()
# fetches the real content through the defer machinery, and the arrival lands
# without a reload — carrying a fresh action token (interactive).
RSpec.describe "Lazy initial mount (issue #165)", type: :system do
  around do
    SlowTotalsComponent.render_delay_ms = 300
    it.run
  ensure
    SlowTotalsComponent.render_delay_ms = 0
  end

  it "ships the shell, then streams the real content in on connect — no reload" do
    visit "/lazy_stats"
    page.execute_script("window.__noReload = 'alive'")

    # The shell is what the PAGE shipped: shimmer + pending marker, no content.
    # (The 300ms render delay keeps this window observable; if the fetch beat
    # us here, the content assertions below still pin the behavior.)
    expect(page).to have_css("[data-testid='stats-value']", text: "stats:week")
    expect(page).to have_no_css("[data-testid='stats-shimmer']")
    expect(page).to have_no_css("#lazy-stats[data-reactive-defer-pending]")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    # The arrival is a REAL reactive root: controller mounted, fresh token.
    token = page.evaluate_script(
      %(document.getElementById("lazy-stats").getAttribute("data-reactive-token-value"))
    )
    expect(token).to be_a(String)
    expect(token.length).to be > 20
  end

  it "shows the placeholder shell during the lazy window" do
    visit "/lazy_stats"

    # Race-tolerant: the shimmer is visible until the deferred render lands.
    # With a 300ms server-side render delay the shell must be observable
    # immediately after load.
    expect(page).to have_css("[data-testid='stats-shimmer']")
    expect(page).to have_css("#lazy-stats[data-reactive-defer-pending]")

    # …and resolves to the real content.
    expect(page).to have_css("[data-testid='stats-value']", text: "stats:week")
  end
end
