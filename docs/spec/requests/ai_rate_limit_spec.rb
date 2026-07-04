# frozen_string_literal: true

require 'rails_helper'

# The public, unauthenticated AI endpoints (/mcp, /llms*, /docs/search) are
# throttled per-IP by Rack::Attack (config/initializers/rack_attack.rb) so a
# scraper or runaway agent can't dominate a server. In test the throttle counts
# in a real MemoryStore (Rails.cache is NullStore there), so the limit is
# exercisable. 60 req/min/IP → the 61st in a window is a 429 with Retry-After.
RSpec.describe 'AI endpoint rate limiting', type: :request do
  before { Rack::Attack.cache.store.clear }
  after { Rack::Attack.cache.store.clear }

  it 'lets a normal burst through and 429s past the per-IP limit' do
    60.times do
      get '/llms.txt'
      expect(response).to have_http_status(:ok)
    end

    get '/llms.txt'
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After']).to be_present
  end

  it 'throttles the /mcp endpoint on the same per-IP budget' do
    60.times { get '/llms.txt' } # consume the shared AI budget
    post '/mcp',
         params: { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'does not throttle ordinary doc pages' do
    70.times do
      get '/docs/architecture'
      expect(response).to have_http_status(:ok)
    end
  end
end
