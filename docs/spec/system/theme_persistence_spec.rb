# frozen_string_literal: true

require 'system_helper'

# The theme choice is a global sticky preference (docs-nav controller +
# localStorage). Picking a theme must survive navigation with no flash of the
# server default — the anti-flash <head> script restores it before first paint.
RSpec.describe 'Theme persistence', type: :system do
  it 'remembers the chosen theme across navigation' do
    visit '/docs/architecture'
    expect(page).to have_css('html[data-theme]')

    open_theme_menu
    find('[data-testid="theme-synthwave"]', visible: :all).click

    # Applied immediately.
    expect(page).to have_css('html[data-theme="synthwave"]')

    # Persisted: a fresh navigation keeps synthwave (no revert to the default).
    visit '/docs/security'
    expect(page).to have_css('html[data-theme="synthwave"]')
  end

  private

  def open_theme_menu
    find('div[role="button"]', text: 'Theme').click
  rescue Capybara::ElementNotFound
    # The dropdown button may be icon-only depending on width; click by testid area.
    first('.dropdown-end [role="button"]').click
  end
end
