# frozen_string_literal: true

require 'system_helper'

# The Project board flagship (issue #216) in a real browser: menu-driven lane
# moves with live count badges (reactive:js text ops), per-lane composers,
# Enter-to-save inline rename (morph — the input survives), confirm-gated
# archive, and the effect-style picker riding signed state. Cross-tab delivery
# is asserted at the request level (broadcast specs) per the docs convention —
# the demo site's cable adapter is in-process.
RSpec.describe 'Project board', type: :system do
  # System specs hit a real server on a separate DB connection — seed
  # explicitly per example, never rely on transactional fixtures.
  before { Card.delete_all }

  def demo = first("[data-testid='live-example-demo']")

  it 'moves a card across lanes with live counts, twice, without a reload' do
    Card.create!(title: 'Ship the board', lane: 'todo', position: 1)
    visit '/docs/example-project-board'
    expect(page).to have_css("[data-testid='count-todo']", text: '1')

    page.execute_script("window.__noReload = 'alive'")

    within demo do
      # The row carries the DECLARED effect attrs (issue #215) — static proof
      # the effects wiring reached the DOM, no animation-timing race.
      expect(page).to have_css("[data-testid='board-card'][data-reactive-effect-exit='fade']")

      find("[data-testid='move-doing']").click
      # The card's title lives in an input VALUE — assert via have_field
      # scoped to the destination lane (text: can't see input values).
      within "[data-testid='lane-doing']" do
        expect(page).to have_field('title', with: 'Ship the board')
      end
      expect(page).to have_css("[data-testid='count-todo']", text: '0')
      expect(page).to have_css("[data-testid='count-doing']", text: '1')

      # A second move proves the appended row arrived with a FRESH token
      # (the add-once-only regression class, cosmos#1939).
      find("[data-testid='move-done']").click
      within "[data-testid='lane-done']" do
        expect(page).to have_field('title', with: 'Ship the board')
      end
      expect(page).to have_css("[data-testid='count-done']", text: '1')
      expect(page).to have_css("[data-testid='count-doing']", text: '0')
    end

    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'adds a card from a lane composer and flashes on a blank title' do
    visit '/docs/example-project-board'

    within demo do
      find("[data-testid='new-card-doing']").fill_in(with: 'Write the docs page')
      find("[data-testid='add-doing']").click
      within "[data-testid='lane-doing']" do
        expect(page).to have_field('title', with: 'Write the docs page')
      end
      expect(page).to have_css("[data-testid='count-doing']", text: '1')
      # The board replace cleared the composer (the have_css above is the
      # barrier — the fresh render has landed).
      expect(find("[data-testid='new-card-doing']").value).to eq('')

      find("[data-testid='add-todo']").click # blank title
    end
    expect(page).to have_css('#flash', text: 'A card needs a title')
  end

  it 'renames inline on Enter — the morph keeps the row in place' do
    card = Card.create!(title: 'Old name', lane: 'todo', position: 1)
    visit '/docs/example-project-board'

    within demo do
      input = find("[data-testid='card-title']")
      input.fill_in(with: 'New name')
      input.send_keys(:enter)
      expect(page).to have_field('title', with: 'New name')
    end
    expect(Card.find(card.id).title).to eq('New name')
  end

  it 'archives through the confirm gate and repaints the count' do
    Card.create!(title: 'Done with this', lane: 'done', position: 1)
    visit '/docs/example-project-board'
    expect(page).to have_css("[data-testid='count-done']", text: '1')

    within demo do
      accept_confirm { find("[data-testid='archive-card']").click }
      expect(page).to have_no_css("[data-testid='board-card']")
      expect(page).to have_css("[data-testid='count-done']", text: '0')
    end
    expect(page).to have_css('#flash', text: 'Card archived')
  end

  it 'keeps the picked effect style across round trips (signed state)' do
    Card.create!(title: 'Style me', lane: 'todo', position: 1)
    visit '/docs/example-project-board'

    within demo do
      find("[data-testid='style-scale']").click
      expect(page).to have_css("[data-testid='style-scale'].btn-active")

      # The pick survives the next action's round trip — it rides the signed
      # state, not the DOM.
      find("[data-testid='move-doing']").click
      expect(page).to have_css("[data-testid='count-doing']", text: '1')
      expect(page).to have_css("[data-testid='style-scale'].btn-active")
    end
  end
end
