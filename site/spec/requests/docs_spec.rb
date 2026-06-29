# frozen_string_literal: true

require 'rails_helper'

# The reference docs render from Markdown as Phlex pages.
RSpec.describe 'Docs pages', type: :request do
  it 'renders every registered doc' do
    Doc.all.each do |doc|
      get "/docs/#{doc.slug}"
      expect(response).to have_http_status(:ok), "expected #{doc.slug} to render"
      expect(response.body).to include('<article')
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
