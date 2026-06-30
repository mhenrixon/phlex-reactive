# frozen_string_literal: true

# Server-side registry of the ContextSwitcherComponent's options. Doc pages
# reference a registry by id; the component looks the options up here, so the
# client only ever carries the chosen key (signed into the token), never the
# content. Frozen — content is not client-trusted state.
module DocContexts
  REGISTRIES = {
    'transport' => [
      {
        key: 'action_cable',
        label: 'Action Cable',
        summary: 'Works out of the box. Broadcasts ride over WebSocket via Action Cable (needs Redis or solid_cable).',
        filename: 'config/cable.yml',
        lexer: :yaml,
        code: <<~YAML
          production:
            adapter: redis
            url: <%= ENV.fetch("REDIS_URL") %>
        YAML
      },
      {
        key: 'pgbus',
        label: 'pgbus',
        summary: 'Replaces the transport with Postgres SSE. Broadcasts route over ' \
                 'pgbus automatically — your phlex-reactive code is identical.',
        filename: 'Gemfile',
        lexer: :ruby,
        code: <<~RUBY
          gem "pgbus"
          gem "phlex-reactive"
          # No Redis, no Action Cable. One Postgres — transactional,
          # reconnect-safe broadcasts with zero code changes.
        RUBY
      }
    ]
  }.freeze

  def self.options(registry)
    REGISTRIES.fetch(registry.to_s, [])
  end
end
