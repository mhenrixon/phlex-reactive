# frozen_string_literal: true

require 'system_helper'

# docs-kit's Docs::Example multi-language code group: the docs-nav controller
# remembers the chosen language GLOBALLY (localStorage) and syncs every group on
# the page — and across navigations. Client-only, no server round-trip.
RSpec.describe 'Multi-language code examples', type: :system do
  it 'switches language, syncs all groups, and persists across navigation' do
    visit '/_test/code_example'

    # Two groups, each defaulting to the first language (Ruby) visible.
    expect(page).to have_css('[data-testid="code-lang-ruby"]', count: 2)
    within(first('[data-docs-nav-target="codeGroup"]')) do
      expect(page).to have_text('Anthropic::Client.new')
    end

    # Switch the FIRST group to Python — the SECOND group syncs too (global).
    within(first('[data-docs-nav-target="codeGroup"]')) do
      find('[data-testid="code-lang-python"]').click
    end

    groups = all('[data-docs-nav-target="codeGroup"]')
    within(groups[0]) { expect(page).to have_text('anthropic.Anthropic()') }
    within(groups[1]) { expect(page).to have_text('client.messages.create()') }

    # Persist across a navigation: re-visiting still shows Python.
    visit '/_test/code_example'
    within(first('[data-docs-nav-target="codeGroup"]')) do
      expect(page).to have_text('anthropic.Anthropic()')
      # The Python tab is the active one.
      expect(page).to have_css('[data-testid="code-lang-python"].tab-active')
    end
  end
end
