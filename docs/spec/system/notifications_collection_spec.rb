# frozen_string_literal: true

require 'system_helper'

# reactive_collection in a real browser: add appends a row + bumps the count +
# clears the empty-state; dismiss removes it optimistically + restores the empty
# state + shows a self-dismissing flash — all as single reply calls.
RSpec.describe 'Reactive collections', type: :system do
  before { Notification.delete_all }

  it 'adds a row and bumps the running count' do
    visit '/docs/example-collections'
    expect(page).to have_css("[data-testid='empty-state']")
    expect(page).to have_css("[data-testid='count']", text: '0')

    find("[data-testid='new-notification']").set('Build finished')
    find("[data-testid='add']").click

    expect(page).to have_css("[data-testid='notification']", count: 1, text: 'Build finished')
    expect(page).to have_css("[data-testid='count']", text: '1')
    expect(page).to have_no_css("[data-testid='empty-state']")
  end

  it 'dismisses a row, restores the empty-state, and shows a self-dismissing flash' do
    visit '/docs/example-collections'
    find("[data-testid='new-notification']").set('Dismiss me')
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='notification']", count: 1)

    find("[data-testid='dismiss']").click

    # The row is gone, the count is back to zero, and the empty-state returns.
    expect(page).to have_no_css("[data-testid='notification']")
    expect(page).to have_css("[data-testid='count']", text: '0')
    expect(page).to have_css("[data-testid='empty-state']")

    # The self-dismissing flash appeared, then clears itself (dismiss_after: 3 s).
    expect(page).to have_css("[data-testid='flash']", text: 'Notification dismissed')
    expect(page).to have_no_css("[data-testid='flash']", text: 'Notification dismissed', wait: 5)
  end
end
