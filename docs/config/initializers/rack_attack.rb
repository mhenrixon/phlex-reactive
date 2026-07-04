# frozen_string_literal: true

# Throttle the public, unauthenticated AI/tooling endpoints docs-kit exposes:
#   POST /mcp            — the Model Context Protocol server (JSON-RPC)
#   GET  /llms.txt       — the llmstxt.org index
#   GET  /llms-full.txt  — every page concatenated
#   GET  /docs/search    — the search index (html + json)
#
# These are read-only over already-public content, but they're outward-facing and
# cheap to hammer (llms-full.txt concatenates every page; search scans the index),
# so a per-IP cap keeps a scraper or a runaway agent from dominating a single
# server. The docs-kit controllers are bare ActionController::Base subclasses, so
# a controller-level `rate_limit` can't reach them — a Rack middleware can.
#
# Rack::Attack counts in its own cache. Rails.cache is a MemoryStore in dev and a
# per-server FileStore in production (both fine for a per-server throttle); it's a
# NullStore in test, so give Rack::Attack an explicit MemoryStore there so the
# throttle is exercisable in specs and never silently a no-op.
Rack::Attack.cache.store =
  if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    Rails.cache
  end

# 60 requests/minute per IP across the AI endpoints — generous for a human or a
# well-behaved agent, a wall for a scraper. Over the limit → 429.
Rack::Attack.throttle('ai-endpoints/ip', limit: 60, period: 60) do |request|
  path = request.path
  ai_path =
    path == '/mcp' ||
    path == '/llms.txt' ||
    path == '/llms-full.txt' ||
    path == '/docs/search' ||
    path.start_with?('/docs/search.')

  request.ip if ai_path
end

# A small, honest 429 (plus Retry-After) instead of Rack::Attack's blank default.
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data'] || {}
  retry_after = (match_data[:period] || 60).to_i
  [
    429,
    { 'Content-Type' => 'text/plain', 'Retry-After' => retry_after.to_s },
    ["Rate limit exceeded. Retry in #{retry_after}s.\n"]
  ]
end
