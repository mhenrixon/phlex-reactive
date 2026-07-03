# frozen_string_literal: true

require 'system_helper'

# Inline edit + dirty tracking in a real browser: click-to-edit shows the field,
# Save persists and returns to display, and the "Unsaved" badge appears on the
# first keystroke and clears after a save — all without a full-page reload.
RSpec.describe 'Inline edit + dirty tracking', type: :system do
  before { Todo.delete_all }

  it 'clicks to edit, saves, and returns to the display value' do
    visit '/docs/example-inline-edit'
    page.execute_script("window.__noReload = 'alive'")

    within first("[data-testid='live-example-demo']") do
      find("[data-testid='display']").click
      field = find("[data-testid='field']")
      field.set('Renamed in place')
      find("[data-testid='save']").click

      # Back to display mode, showing the persisted value (no field visible).
      expect(page).to have_css("[data-testid='display']", text: 'Renamed in place')
      expect(page).to have_no_css("[data-testid='field']")
    end

    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'cancels an edit back to display mode without persisting' do
    visit '/docs/example-inline-edit'

    within first("[data-testid='live-example-demo']") do
      find("[data-testid='display']").click
      find("[data-testid='field']").set('discard this')
      find("[data-testid='cancel']").click

      # Back in display mode (field gone) and the discarded text was not saved.
      expect(page).to have_css("[data-testid='display']")
      expect(page).to have_no_css("[data-testid='field']")
      expect(page).to have_no_text('discard this')
    end
  end

  it 'shows the Unsaved badge on edit and clears it after save' do
    visit '/docs/example-inline-edit'

    # The dirty-form demo is the SECOND live example on the page.
    within all("[data-testid='live-example-demo']")[1] do
      expect(page).to have_no_css("[data-testid='dirty-badge']", visible: :visible)

      find("[data-testid='title']").set('changed value')
      expect(page).to have_css("[data-testid='dirty-badge']", visible: :visible, text: 'Unsaved')

      find("[data-testid='save']").click
      # After the morph the field's default resets to the saved value → clean.
      expect(page).to have_no_css("[data-testid='dirty-badge']", visible: :visible)
      expect(page).to have_css("[data-testid='current']", text: 'changed value')
    end
  end
end
