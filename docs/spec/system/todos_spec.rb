# frozen_string_literal: true

require 'system_helper'

# The live todo list in a real browser: optimistic archive, the client-only Clear
# button (zero fetch), and the empty-state — the richer behavior the example page
# documents, now proven end-to-end.
RSpec.describe 'Live todo list', type: :system do
  # System specs drive a real server on a separate connection, so
  # use_transactional_fixtures does NOT roll back rows the server created.
  before { Todo.delete_all }

  it 'shows the empty-state until the first todo is added' do
    visit '/docs/example-todo-list'
    expect(page).to have_css("[data-testid='todos-empty']")

    find("[data-testid='new-todo']").set('first thing')
    find("[data-testid='add']").click

    expect(page).to have_css("[data-testid='todo']", count: 1)
    expect(page).to have_no_css("[data-testid='todos-empty']")
  end

  it 'archives a row optimistically (it hides in the same gesture)' do
    visit '/docs/example-todo-list'
    find("[data-testid='new-todo']").set('archive me')
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='todo']", count: 1)

    within first("[data-testid='todo']") do
      find("[data-testid='archive']").click
    end

    # reply.remove drops the row; the optimistic hide meant it disappeared the
    # instant the button was clicked.
    expect(page).to have_no_css("[data-testid='todo']")
  end

  it 'toggles the tips hint client-side with ZERO round trip' do
    visit '/docs/example-todo-list'
    page.execute_script("window.__noReload = 'alive'")

    # The hint starts hidden; a client-only op flips it with no token, no POST.
    expect(page).to have_no_css("[data-testid='todo-tips']", visible: :visible)
    find("[data-testid='tips-toggle']").click
    expect(page).to have_css("[data-testid='todo-tips']", visible: :visible, text: 'Press Enter')

    # No todo was created and no full-page reload happened — pure client op.
    expect(page).to have_no_css("[data-testid='todo']")
    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'toggles a row done and marks it via the re-render' do
    visit '/docs/example-todo-list'
    find("[data-testid='new-todo']").set('toggle me')
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='todo']", count: 1)

    within first("[data-testid='todo']") do
      find("[data-testid='toggle']").click
    end

    expect(page).to have_css("[data-testid='todo'][data-done='true']")
  end
end
