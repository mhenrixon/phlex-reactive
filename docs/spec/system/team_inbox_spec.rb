# frozen_string_literal: true

require 'system_helper'

# The flagship Team inbox in a real browser: the happy path (kebab → archive
# removes the row optimistically + count drops) AND the optimistic-revert path (a
# locked message's archive denies, so the row snaps back).
RSpec.describe 'Team inbox', type: :system do
  before { InboxMessage.delete_all }

  it 'archives a message via the kebab menu and drops the count' do
    InboxMessage.create!(subject: 'Deploy finished', sender: 'ci')
    visit '/docs/example-team-inbox'

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_css("[data-testid='inbox-row']", count: 1)
      expect(page).to have_css("[data-testid='inbox-count']", text: '1')

      # The kebab is a pure client op — open it, then Archive.
      within first("[data-testid='inbox-row']") do
        find("[data-testid='kebab']").click
        find("[data-testid='archive']").click
      end

      expect(page).to have_no_css("[data-testid='inbox-row']")
      expect(page).to have_css("[data-testid='inbox-count']", text: '0')
      expect(page).to have_css("[data-testid='inbox-empty']")
    end
  end

  it 'reverts the optimistic hide when archiving a locked message is denied' do
    InboxMessage.create!(subject: 'Compliance hold', sender: 'locked')
    visit '/docs/example-team-inbox'

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_css("[data-testid='inbox-row']", count: 1)

      within first("[data-testid='inbox-row']") do
        find("[data-testid='kebab']").click
        find("[data-testid='archive']").click
      end

      # The archive denies (403), so the optimistically-hidden row SNAPS BACK and
      # the count is unchanged — the record was never destroyed.
      expect(page).to have_css("[data-testid='inbox-row']", count: 1, text: 'Compliance hold')
      expect(page).to have_css("[data-testid='inbox-count']", text: '1')
    end

    expect(InboxMessage.where(subject: 'Compliance hold')).to exist
  end

  it 'pushes a new message with Simulate incoming' do
    visit '/docs/example-team-inbox'

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_css("[data-testid='inbox-empty']")
      find("[data-testid='simulate-incoming']").click

      expect(page).to have_css("[data-testid='inbox-row']", count: 1)
      expect(page).to have_no_css("[data-testid='inbox-empty']")
      expect(page).to have_css("[data-testid='inbox-count']", text: '1')
    end
  end
end
