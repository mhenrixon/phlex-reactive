# frozen_string_literal: true

require 'system_helper'

# Issue #95: a component whose entire interactivity is on_client ops. The contract
# is ZERO fetches — a fetch spy proves no click ever posts to the action endpoint.
RSpec.describe 'Client-only ops', type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetches = 0
      const original = window.fetch
      window.fetch = function () { window.__fetches++; return original.apply(this, arguments) }
    JS
  end

  it 'switches tabs, toggles a menu, and opens a drawer with ZERO fetches' do
    visit '/docs/example-client-ops'
    install_fetch_spy

    within first("[data-testid='live-example-demo']") do
      # Tabs: panel 1 shown by default, panel 2 hidden.
      expect(page).to have_css("[data-testid='panel-1']", visible: :visible)
      expect(page).to have_no_css("[data-testid='panel-2']", visible: :visible)

      find("[data-testid='tab-2']").click
      expect(page).to have_css("[data-testid='panel-2']", visible: :visible)
      expect(page).to have_no_css("[data-testid='panel-1']", visible: :visible)

      # Menu: open it with a client op.
      find("[data-testid='menu-open']").click
      expect(page).to have_css("[data-testid='menu']", visible: :visible)

      # Drawer: opens (fade) and its first button receives focus.
      find("[data-testid='drawer-open']").click
      expect(page).to have_css("[data-testid='drawer']", visible: :visible)
    end

    # Click clearly OUTSIDE the component (the page heading) — the root's
    # outside-close op hides the menu with no round trip.
    find('h1').click
    expect(page).to have_no_css("[data-testid='menu']", visible: :visible)

    # The #95 contract: not a single fetch fired across all those interactions.
    expect(page.evaluate_script('window.__fetches')).to eq(0)
  end
end
