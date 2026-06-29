# frozen_string_literal: true

require 'system_helper'

# Visual smoke: a hand-authored doc page renders with a real masthead, sections,
# and highlighted code (the old markdown pipeline rendered raw frontmatter with
# no typography).
RSpec.describe 'Doc page rendering', type: :system do
  it 'renders the security page with structured content' do
    visit '/docs/security'

    expect(page).to have_css('h1', text: 'Security')
    expect(page).to have_css('section')                 # Docs::Section
    expect(page).to have_css('.code-highlight')         # a Rouge code block
    # Frontmatter must NOT leak (the old bug).
    expect(page).to have_no_text('layout: default')
    expect(page).to have_no_text('nav_order:')
  end

  it 'renders the transport page with the reactive context switcher' do
    visit '/docs/transport-pgbus'

    expect(page).to have_css('h1', text: 'Transport')
    expect(page).to have_css("[data-testid='context-tab-action_cable']")
    expect(page).to have_css('.code-highlight')
  end
end
