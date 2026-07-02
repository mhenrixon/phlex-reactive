# frozen_string_literal: true

require 'system_helper'

# The ported demos in a real browser: each round-trips with no full-page reload,
# and the 3-tab panel (Demo / Call-site / Component) is present on every page.
RSpec.describe 'Demo gallery', type: :system do
  # System specs drive the app through a real server on a separate connection, so
  # use_transactional_fixtures does NOT roll back rows the server created. Clear
  # the todos this file adds so each example starts from a known-empty list.
  before { Todo.delete_all }

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

    # Drive the composer by its stable testid — the row rename inputs also carry
    # name="title", so fill_in 'title' would be ambiguous once a row exists.
    find("[data-testid='new-todo']").set('buy oat milk')
    find("[data-testid='add']").click

    # The new row appears (waiting matcher = the async barrier).
    expect(page).to have_css("[data-testid='todo']", count: 1)
    within first("[data-testid='todo']") do
      expect(page).to have_css("[data-testid='todo-title']")
      find("[data-testid='toggle']").click
    end

    # After toggle the row is marked done (data attribute flips via re-render).
    expect(page).to have_css("[data-testid='todo'][data-done='true']")
  end

  it 'adds a todo by pressing Enter in the field (key: "Enter")' do
    visit '/demos/todos'
    page.execute_script("window.__noReload = 'alive'")

    # Press Enter in the composer instead of clicking Add — the on(:add, key:
    # "Enter") trigger must dispatch the same action.
    field = find("[data-testid='new-todo']")
    field.set('press enter to add')
    field.send_keys(:enter)

    expect(page).to have_css("[data-testid='todo']", count: 1)
    within first("[data-testid='todo']") do
      expect(page).to have_field('title', with: 'press enter to add')
    end
    # No full-page reload — the keypress round-tripped reactively.
    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'rebalances the payment split live so the amounts always sum to the total' do
    visit '/demos/payment-split'

    expect(page).to have_css("[data-testid='split-remainder']", text: 'Balanced')

    # Push allowance up; the peers must absorb the difference to keep the sum.
    field = find("[data-testid='split-allowance']")
    field.set('900')
    field.send_keys(:tab) # blur → change event fires the rebalance

    expect(page).to have_css("[data-testid='split-remainder']", text: 'Balanced')
    expect(page).to have_css("[data-testid='split-remainder']", text: '= 1000')
  end

  it 'renders the 3-tab panel on every demo page' do
    %w[searchable-combobox counter payment-split todos chat].each do |slug|
      visit "/demos/#{slug}"
      expect(page).to have_css("[data-testid='demo-panel']")
      expect(page).to have_css("[data-testid='tab-demo']")
      expect(page).to have_css("[data-testid='tab-call-site']")
      expect(page).to have_css("[data-testid='tab-component']")
    end
  end
end
