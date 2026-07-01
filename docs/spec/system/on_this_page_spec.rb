# frozen_string_literal: true

require 'system_helper'

# The docs-kit "On this page" auto-TOC: the docs-nav Stimulus controller collects
# the current page's Docs::Section anchors from the DOM and renders them in the
# configured placement (this site uses the default :panel), highlighting the
# section you're reading via scroll-spy. Client-only — no server round-trip.
RSpec.describe 'On this page (auto-TOC)', type: :system do
  it 'auto-builds the panel TOC from the page sections', :desktop_only do
    visit '/docs/architecture'

    # The panel slot is filled by the controller with a link per section.
    within('[data-docs-nav-target~="tocRoot"]') do
      expect(page).to have_css('a[data-docs-nav-target="tocLink"]', minimum: 2)
      # Links point at the section anchors on the page.
      expect(page).to have_link('The mental model', href: '#the-mental-model')
    end
  end

  it 'highlights the section link matching the anchor when navigated to', :desktop_only do
    visit '/docs/architecture#the-layers'

    # Give the IntersectionObserver a beat to settle on the anchored section.
    expect(page).to have_css(
      'a[data-docs-nav-target="tocLink"][data-current]', wait: 3
    )
  end

  it 'hides the TOC on a page with too few sections' do
    # The examples-overview page has a single section; the controller hides the
    # panel (tocRoot becomes [hidden]) when there are fewer than the minimum.
    visit '/docs/examples'

    # Wait for the page to render before asserting the absence (avoid a race).
    expect(page).to have_css('h1')
    expect(page).to have_no_css('[data-docs-nav-target~="tocRoot"] a[data-docs-nav-target="tocLink"]')
  end
end
