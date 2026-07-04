# frozen_string_literal: true

require 'rails_helper'

# The docs-kit MCP server (read-only, stateless JSON-RPC over POST) exposes this
# site's docs as agent tools. It's live because the `mcp` gem is bundled, the
# /mcp route is drawn, and c.mcp defaults to true. These specs lock in that the
# three tools respond, that GET/DELETE are rejected, and that enabling MCP makes
# /llms.txt advertise the endpoint — so a regression (gem dropped, route
# recommented, c.mcp flipped) fails loudly.
RSpec.describe 'MCP endpoint', type: :request do
  def rpc(method, params = {})
    post '/mcp',
         params: { jsonrpc: '2.0', id: 1, method:, params: }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
    response.parsed_body
  end

  def tool_text(name, arguments = {})
    result = rpc('tools/call', { name:, arguments: }).fetch('result')
    expect(result['isError']).to be_falsey
    result.dig('content', 0, 'text').to_s
  end

  describe 'tools/list' do
    it 'advertises the three read-only docs tools' do
      names = rpc('tools/list').dig('result', 'tools').pluck('name')
      expect(names).to contain_exactly('list_pages', 'get_page', 'search_docs')
    end
  end

  describe 'tools/call' do
    it 'list_pages returns the authored pages with their slugs and urls' do
      text = tool_text('list_pages')
      expect(text).to include('architecture').and include('/docs/architecture')
    end

    it 'get_page returns one page as Markdown by slug' do
      text = tool_text('get_page', { slug: 'architecture' })
      expect(text).to include('/docs/architecture')
      expect(text).to include('Architecture').or include('re-render')
    end

    it 'search_docs ranks hits for a query' do
      text = tool_text('search_docs', { query: 'broadcast' })
      expect(text).to include('/docs/broadcasting')
    end
  end

  describe 'method handling' do
    it 'rejects GET with 405 (POST-only, stateless — no SSE session)' do
      get '/mcp'
      expect(response).to have_http_status(:method_not_allowed)
    end

    it 'rejects DELETE with 405 (no session to terminate)' do
      delete '/mcp'
      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe '/llms.txt advertises the endpoint' do
    it 'grows a ## MCP section when the endpoint is live' do
      get '/llms.txt'
      expect(response.body).to include('## MCP')
    end
  end
end
