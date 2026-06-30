# frozen_string_literal: true

require 'system_helper'

# daisyUI is wired up: the theme switcher changes the page theme with ZERO custom
# JavaScript (a CSS :has() selector on the checked theme-controller radio drives
# daisyUI's per-theme CSS variables). We prove the variables actually change.
RSpec.describe 'Theming', type: :system do
  it 'switches the daisyUI theme when a theme is chosen' do
    visit '/'

    base_before = primary_color

    # Open the daisyUI dropdown (focus-driven), then choose a distinct theme.
    # daisyUI applies it via a CSS :has() selector — no custom JavaScript.
    find(".dropdown [role='button']", text: 'Theme').click
    find("[data-testid='theme-synthwave']").click

    # The computed --color-primary changes once synthwave is active (waiting).
    expect(page).to satisfy('primary color to change') do
      primary_color != base_before
    end
  end

  private

  # The resolved daisyUI primary color custom property on :root.
  def primary_color
    page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--color-primary').trim()"
    )
  end
end
