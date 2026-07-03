# frozen_string_literal: true

require 'system_helper'

# The live notification bell in a real browser: clicking "Simulate a background
# event" bumps the unread count in place (the actor's own HTTP reply), proving the
# pure-broadcast bell round-trips. (The cross-tab pulse needs a second tab, out of
# scope for a single-session spec — its wire form is covered in the request spec.)
RSpec.describe 'Notification bell', type: :system do
  it 'bumps the unread count when a background event is simulated' do
    visit '/docs/example-notifications'
    page.execute_script("window.__noReload = 'alive'")

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_no_css("[data-testid='bell-count']")

      find("[data-testid='simulate']").click
      expect(page).to have_css("[data-testid='bell-count']", text: '1')

      find("[data-testid='simulate']").click
      expect(page).to have_css("[data-testid='bell-count']", text: '2')
    end

    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end
end
