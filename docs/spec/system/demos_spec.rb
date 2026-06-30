# frozen_string_literal: true

require 'system_helper'

# The ported demos in a real browser: each round-trips with no full-page reload,
# and the 3-tab panel (Demo / Call-site / Component) is present on every page.
RSpec.describe 'Demo gallery', type: :system do
  it 'counter increments in place' do
    visit '/demos/counter'
    page.execute_script("window.__noReload = 'alive'")

    expect(page).to have_css("[data-testid='count']", text: '0')
    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: '1')
    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: '2')
    find("[data-testid='dec']").click
    expect(page).to have_css("[data-testid='count']", text: '1')

    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'todos add and toggle' do
    visit '/demos/todos'

    fill_in 'title', with: 'buy oat milk'
    find("[data-testid='add']").click

    # The new row appears (waiting matcher = the async barrier).
    expect(page).to have_css("[data-testid='todo']", count: 1)
    within first("[data-testid='todo']") do
      expect(page).to have_field('title', with: 'buy oat milk')
      find("[data-testid='toggle']").click
    end

    # After toggle the row is marked done (data attribute flips via re-render).
    expect(page).to have_css("[data-testid='todo'][data-done='true']")
  end

  it 'renders the 3-tab panel on every demo page' do
    %w[searchable-combobox counter todos chat].each do |slug|
      visit "/demos/#{slug}"
      expect(page).to have_css("[data-testid='demo-panel']")
      expect(page).to have_css("[data-testid='tab-demo']")
      expect(page).to have_css("[data-testid='tab-call-site']")
      expect(page).to have_css("[data-testid='tab-component']")
    end
  end
end
