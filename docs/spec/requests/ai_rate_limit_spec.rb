# frozen_string_literal: true

require 'rails_helper'

# The public, unauthenticated AI endpoints (/mcp, /llms*, /docs/search) are
# throttled per-IP by Rack::Attack (config/initializers/rack_attack.rb) so a
# scraper or runaway agent can't dominate a server. In test the throttle counts
# in a real MemoryStore (Rails.cache is NullStore there), so the limit is
# exercisable. 60 req/min/IP → the 61st in a window is a 429 with Retry-After.
RSpec.describe 'AI endpoint rate limiting', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Rack::Attack buckets counts by epoch window (Time.now.to_i / period), so a
  # 60-request burst that starts near second :59 straddles TWO buckets — the
  # 61st request lands in the fresh window with a count of 1 and sails through
  # with a 200 (a real CI flake: the falcon demo-site job hit the boundary).
  # Pin the clock mid-window so the whole burst always counts in ONE bucket.
  before do
    travel_to Time.zone.parse('2026-01-01 12:00:05')
    Rack::Attack.cache.store.clear
  end

  # (No explicit travel_back — Rails resets stubbed time after each example.)
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
