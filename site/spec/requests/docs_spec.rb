# frozen_string_literal: true

require 'rails_helper'

# The reference docs are hand-authored Phlex pages (self-contained, so they
# survive when the gem's docs/ folder is gone at deploy).
RSpec.describe 'Docs pages', type: :request do
  # Only docs whose Phlex page class exists are routable yet; the rest are being
  # authored. Each authored page must render through the doc shell.
  authored = Doc.all.select(&:view_class)

  it 'has at least the foundational pages authored' do
    expect(authored.map(&:slug)).to include('architecture', 'transport-pgbus')
  end

  authored.each do |doc|
    it "renders the #{doc.slug} page" do
      get "/docs/#{doc.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1') # the doc Header
    end
  end

  it 'renders the doc title as a heading' do
    get '/docs/architecture'
    expect(response.body).to include('Architecture')
  end

  it '404s a doc whose page is not authored yet' do
    get '/docs/does-not-exist'
    expect(response).to have_http_status(:not_found)
  end
end
