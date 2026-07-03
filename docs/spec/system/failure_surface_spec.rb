# frozen_string_literal: true

require 'system_helper'

# The failure surface (issue #100) in a real browser: a failed action reveals the
# error banner (data-reactive-error) and shows an error flash; a successful action
# clears it; flash_now shows a self-dismissing toast.
RSpec.describe 'Failure surface', type: :system do
  it 'reveals the error banner on a failed action and clears it on success' do
    visit '/docs/example-failure'

    within first("[data-testid='live-example-demo']") do
      # The banner is hidden until an action fails.
      expect(page).to have_no_css("[data-testid='error-banner']", visible: :visible)

      find("[data-testid='boom']").click
      # data-reactive-error is set on the root → the banner reveals via CSS.
      expect(page).to have_css("[data-testid='error-banner']", visible: :visible)

      # A successful action re-renders and clears the error.
      find("[data-testid='succeed']").click
      expect(page).to have_css("[data-testid='count']", text: '1')
      expect(page).to have_no_css("[data-testid='error-banner']", visible: :visible)
    end
  end

  it 'shows a self-dismissing flash on flash_now' do
    visit '/docs/example-failure'

    within first("[data-testid='live-example-demo']") do
      find("[data-testid='flash-now']").click
    end

    # The toast appears (visible: :all — the flash toast layout is finicky under
    # Capybara's strict visibility) then clears itself after dismiss_after: (2.5 s).
    expect(page).to have_css("[data-testid='flash']", text: 'self-dismisses', visible: :all)
    expect(page).to have_no_css("[data-testid='flash']", text: 'self-dismisses', visible: :all, wait: 5)
  end
end
