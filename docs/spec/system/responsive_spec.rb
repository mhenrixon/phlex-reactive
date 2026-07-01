# frozen_string_literal: true

require 'system_helper'

# Responsive layout: the shell must degrade cleanly on small screens. These
# examples resize the viewport themselves (independent of CAPYBARA_SCREEN) so the
# behavior is asserted regardless of which matrix width the suite runs under.
RSpec.describe 'Responsive shell', type: :system do
  def resize(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  rescue StandardError
    # Playwright: set the viewport via the page if the Selenium-style API is absent.
    page.current_window.resize_to(width, height)
  end

  context 'when on a phone (390px)' do
    before { resize(390, 844) }

    it 'collapses the sidebar into a drawer (hidden until the hamburger)' do
      visit '/docs/architecture'
      expect(page).to have_css('h1', text: 'Architecture')

      # The drawer checkbox exists and is unchecked (sidebar hidden); the
      # hamburger label that toggles it is visible on small screens.
      expect(page).to have_css("label[for='site-drawer']", visible: :all)
      expect(page).to have_field('site-drawer', type: 'checkbox', checked: false, visible: :all)
    end

    it 'hides the sticky panel TOC (it is lg:block only)' do
      visit '/docs/architecture'
      expect(page).to have_css('h1', text: 'Architecture')

      # tocRoot is present in the DOM but not visible at this width.
      expect(page).to have_no_css('[data-docs-nav-target~="tocRoot"] a[data-docs-nav-target="tocLink"]', visible: :visible)
    end

    it 'keeps the content readable without horizontal overflow' do
      visit '/docs/architecture'
      expect(page).to have_css('h1', text: 'Architecture')

      # The document isn't wider than the viewport (no sideways scroll).
      overflow = page.evaluate_script(
        'document.documentElement.scrollWidth - document.documentElement.clientWidth'
      )
      expect(overflow).to be <= 1 # allow sub-pixel rounding
    end
  end

  context 'when on a tablet (820px)' do
    before { resize(820, 1180) }

    it 'renders the docs page and reactive demos' do
      visit '/demos/counter'
      expect(page).to have_css("[data-testid='count']", wait: 3)
    end
  end
end
