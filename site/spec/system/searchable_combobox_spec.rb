# frozen_string_literal: true

require 'system_helper'

# The headline interactive demo (issue #51) in a real browser: typing filters the
# list via a debounced reactive round trip, focus + caret survive the morph (the
# whole point of reply.morph over reply.replace), and clicking an option reports
# the selection back — all with no custom JavaScript and no full-page reload.
RSpec.describe 'Searchable combobox', type: :system do
  it 'filters as you type while keeping focus and the typed value' do
    visit '/demos/searchable-combobox'
    page.execute_script("window.__noReload = 'alive'")

    field = find("[data-testid='combobox-query']")
    field.click
    field.set('ru')

    # The debounced `search` morphs the root in place. Waiting matcher = the
    # async barrier for the round trip.
    within("[data-testid='combobox-results']") do
      expect(page).to have_css("[data-testid='combobox-option-ruby']")
      expect(page).to have_css("[data-testid='combobox-option-rust']")
      expect(page).to have_no_css("[data-testid='combobox-option-elixir']")
    end

    # The decisive morph assertion: the field is STILL the active element after
    # the morph (a plain replace would have blurred it to <body>)...
    active_testid = page.evaluate_script('document.activeElement && document.activeElement.dataset.testid')
    expect(active_testid).to eq('combobox-query')

    # ...and still carries the typed value (caret/value preserved through morph).
    expect(page).to have_field('query', with: 'ru')

    # No full-page reload happened.
    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'reports the chosen option back as the selection' do
    visit '/demos/searchable-combobox'

    find("[data-testid='combobox-query']").set('ru')
    expect(page).to have_css("[data-testid='combobox-option-ruby']")

    find("[data-testid='combobox-option-ruby']").click

    # The selection chip appears, driven entirely by server state (the signed
    # token now carries selected_name).
    expect(page).to have_css("[data-testid='combobox-selection']", text: 'Ruby')
  end

  it 'shows an empty state for a query that matches nothing' do
    visit '/demos/searchable-combobox'

    find("[data-testid='combobox-query']").set('zzzznope')

    expect(page).to have_css("[data-testid='combobox-empty']", text: 'No matches')
  end
end
