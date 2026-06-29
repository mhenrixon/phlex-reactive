# frozen_string_literal: true

require 'rails_helper'

# The reference docs are hand-authored Phlex pages (self-contained, so they
# survive when the gem's docs/ folder is gone at deploy). Every registered doc
# has a page class and renders through the doc shell.
RSpec.describe 'Docs pages', type: :request do
  Doc.all.each do |doc|
    it "renders the #{doc.slug} page" do
      expect(doc.view_class).to be_present, "no Phlex page for #{doc.slug}"
      get "/docs/#{doc.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1') # the doc Header
    end
  end

  it 'renders the doc title as a heading' do
    get '/docs/architecture'
    expect(response.body).to include('Architecture')
  end

  it '404s an unknown doc slug' do
    get '/docs/does-not-exist'
    expect(response).to have_http_status(:not_found)
  end
end
