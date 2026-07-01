# frozen_string_literal: true

require 'system_helper'

# The docs-kit docs-nav Stimulus controller: it persists sidebar collapse state
# to localStorage (client-only UI state — no server round-trip) so the sidebar
# stays how the reader left it across page navigations.
RSpec.describe 'Docs sidebar collapse persistence', type: :system do
  it 'remembers a collapsed sub-group across navigation' do
    visit '/docs/installation'

    # The "Examples" sub-group is a <details open> with a menu-title summary.
    examples = find('summary.menu-title', text: 'Examples')
    examples_details = examples.find(:xpath, './..') # the <details>

    expect(examples_details['open']).to be_truthy

    # Collapse it (native <details> toggle) and let the controller persist.
    examples.click
    expect(examples.find(:xpath, './..')['open']).to be_falsey

    # Navigate to another page; the sidebar re-renders server-side with the
    # section OPEN by default, but the controller restores the collapsed state.
    visit '/docs/architecture'

    restored = find('summary.menu-title', text: 'Examples').find(:xpath, './..')
    expect(restored['open']).to be_falsey
  end

  it 'renders the sidebar under the docs-nav controller' do
    visit '/docs/installation'

    expect(page).to have_css('[data-controller~="docs-nav"]')
  end
end
