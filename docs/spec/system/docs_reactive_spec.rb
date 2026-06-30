# frozen_string_literal: true

require 'system_helper'

# The docs dogfood the gem: a reactive context switcher and a reactive modal,
# both driven by signed-token reactive round trips with no custom JavaScript.
RSpec.describe 'Reactive docs widgets', type: :system do
  it 'switches context reactively (transport: Action Cable ↔ pgbus)' do
    visit '/docs/transport-pgbus'

    within "[data-testid='context-panel']" do
      expect(page).to have_text('cable.yml')
    end

    find("[data-testid='context-tab-pgbus']").click

    # The panel re-renders server-side to the pgbus content (the tab is now active).
    expect(page).to have_css("[data-testid='context-tab-pgbus'].tab-active")
    within "[data-testid='context-panel']" do
      expect(page).to have_text('Gemfile')
      expect(page).to have_text('pgbus')
    end
  end

  it 'opens and closes a reactive modal' do
    visit '/docs/architecture'

    # Wait for the trigger, then assert the modal is closed before opening it.
    expect(page).to have_css("[data-testid='modal-open-signed-identity']")
    expect(page).to have_no_css("[data-testid='modal-signed-identity']")
    find("[data-testid='modal-open-signed-identity']").click

    expect(page).to have_css("[data-testid='modal-signed-identity']")
    within "[data-testid='modal-signed-identity']" do
      expect(page).to have_text('token')
    end

    find("[data-testid='modal-close-signed-identity']").click
    expect(page).to have_no_css("[data-testid='modal-signed-identity']")
  end
end
