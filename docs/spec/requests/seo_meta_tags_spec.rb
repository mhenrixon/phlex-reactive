# frozen_string_literal: true

require 'rails_helper'

# docs-kit 1.0.2 emits a full SEO/social <head> (DocsUI::MetaTags) driven by the
# c.seo block and per-page `description`. These assertions run against a REAL
# request (isolated component specs can't resolve og:image through the asset
# pipeline), locking in that the share-card tags render and that og:image points
# at a digested /assets URL that actually exists.
RSpec.describe 'SEO meta tags', type: :request do
  describe 'a documentation page' do
    before { get '/docs/security' }

    it 'renders the per-page meta description' do
      expect(response.body).to match(/<meta name="description" content="Secure phlex-reactive[^"]+">/)
    end

    it 'renders the Open Graph card' do
      expect(response.body).to include('<meta property="og:title" content="Security & threat model · phlex-reactive">')
      expect(response.body).to include('property="og:description"')
      expect(response.body).to include('<meta property="og:type" content="website">')
    end

    it 'renders the Twitter summary_large_image card' do
      expect(response.body).to include('<meta name="twitter:card" content="summary_large_image">')
    end

    it 'resolves og:image to a digested /assets URL' do
      m = response.body.match(/<meta property="og:image" content="([^"]+)">/)
      expect(m).to be_present, 'no og:image tag'
      expect(m[1]).to match(%r{/assets/og/og-\w+\.png})
    end

    it 'renders canonical + theme-color + favicon' do
      expect(response.body).to include('rel="canonical"')
      expect(response.body).to include('<meta name="theme-color" content="#1d232a">')
      expect(response.body).to include('<link rel="icon" href="/favicon.svg">')
    end
  end

  describe 'the landing page' do
    before { get '/' }

    it 'renders a description and an og:image on the root' do
      expect(response.body).to match(/<meta name="description" content="Reactive Phlex[^"]+">/)
      expect(response.body).to match(%r{<meta property="og:image" content="[^"]+/assets/og/og-\w+\.png">})
    end
  end
end
