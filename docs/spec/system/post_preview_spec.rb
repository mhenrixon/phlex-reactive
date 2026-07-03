# frozen_string_literal: true

require 'system_helper'

# reactive_compute + reactive_text in a real browser: the title heading mirrors
# the field and the char counter recomputes IN-BROWSER on input (the "preview" JS
# reducer, no round trip); Save reconciles through the server.
RSpec.describe 'Live compute preview', type: :system do
  before { Todo.delete_all }

  it 'mirrors the title and recomputes the counter with no round trip' do
    visit '/docs/example-payment-split'
    page.execute_script(<<~JS)
      window.__fetches = 0
      const original = window.fetch
      window.fetch = function () { window.__fetches++; return original.apply(this, arguments) }
    JS

    within first("[data-testid='live-example-demo']") do
      field = find("[data-testid='title']")
      field.set('Reactive compute')

      # The identity mirror and the reducer output both update client-side.
      expect(page).to have_css("[data-testid='preview']", text: 'Reactive compute')
      expect(page).to have_css("[data-testid='counter']", text: '16/80')
    end

    # No POST happened for the live preview — it's a pure client compute.
    expect(page.evaluate_script('window.__fetches')).to eq(0)
  end

  it 'reconciles through the server on Save' do
    visit '/docs/example-payment-split'

    within first("[data-testid='live-example-demo']") do
      find("[data-testid='title']").set('Saved value')
      find("[data-testid='save']").click

      # The server-only echo confirms the round trip persisted + reconciled.
      expect(page).to have_css("[data-testid='saved']", text: 'Saved value')
    end
  end
end
