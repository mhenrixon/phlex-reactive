# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class TransportPgbus < DocsUI::Page
        title 'Transport: pgbus vs Action Cable'
        eyebrow 'Guide'
        description 'Compare pgbus and Action Cable for phlex-reactive: transactional after_commit broadcasts, reconnect replay, and exclude:/visible_to: routing on one Postgres'

        def lead
          "phlex-reactive's client → server half is a plain HTTP POST. The server → " \
            'client half (broadcasts) rides on whatever transport turbo-rails is configured with.'
        end

        def content
          drop_in
          choices
          comparison
          transport_opts
          observability
        end

        private

        def drop_in
          DocsUI::Section('Drop-in: nothing in your code changes') do
            DocsUI::Prose() do
              p do
                plain 'With '
                a(href: 'https://github.com/zoolutions/pgbus') { 'pgbus' }
                plain ' installed, '
                code { 'broadcast_to' }
                plain ' AND '
                code { 'turbo_stream_from' }
                plain ' route over Postgres SSE '
                strong { 'automatically' }
                plain ' — with zero code changes. Both transports drive the SAME ' \
                      'broadcast API: the gem\'s '
                code { 'broadcast_to' }
                plain ' (with '
                code { 'replace:' }
                plain '/'
                code { 'append:' }
                plain '/etc.) calls '
                code { '::Turbo::StreamsChannel.*' }
                plain ' unchanged, so swapping the transport is a Gemfile decision, not a rewrite.'
              end
              p do
                plain 'A record opts into durable broadcasting the same way it always would — '
                code { 'broadcasts_to' }
                plain ', now with '
                code { 'durable: true' }
                plain ':'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              class Message < ApplicationRecord
                broadcasts_to ->(m) { [m.room, :messages] }, durable: true
              end
            RUBY
          end
        end

        def choices
          DocsUI::Section('Pick a transport') do
            DocsUI::Prose() do
              p do
                plain 'You have two choices. Toggle below to see the setup for ' \
                      'each — the toggle itself is a reactive component (dogfooding).'
              end
            end
            # Dogfood: the transport switcher IS a reactive component.
            render ContextSwitcherComponent.new(registry: 'transport')
          end
        end

        def comparison
          DocsUI::Section('pgbus vs Action Cable') do
            DocsUI::Prose() do
              p do
                plain 'Action Cable is the default turbo-rails transport. It works, but for ' \
                      'reactive broadcasts it carries four tradeoffs pgbus does not:'
              end
              ul do
                li do
                  strong { 'Needs Redis (or solid_cable)' }
                  plain '. Action Cable requires a separate pub/sub backend. ' \
                        'pgbus needs '
                  strong { 'one Postgres' }
                  plain ' — the database you already run.'
                end
                li do
                  strong { 'Non-transactional' }
                  plain '. An Action Cable broadcast fires immediately, even if the ' \
                        'surrounding transaction later rolls back — a phantom UI update ' \
                        'for a change that never landed. pgbus defers to '
                  code { 'after_commit' }
                  plain ': a rolled-back transaction emits nothing.'
                end
                li do
                  strong { 'Races on subscribe' }
                  plain '. A message broadcast between render and subscribe is lost on ' \
                        'Action Cable. pgbus watermarks and replays it.'
                end
                li do
                  strong { 'No reconnect replay' }
                  plain '. A tab that dropped its Action Cable connection misses whatever ' \
                        'aired while it was gone. pgbus replays from the PGMQ archive on ' \
                        'reconnect ('
                  code { 'Last-Event-ID' }
                  plain ').'
                end
              end
            end
            DocsUI::Callout(:tip) do
              plain 'No Redis, no Action Cable. One Postgres — and your phlex-reactive code is identical.'
            end
          end
        end

        def transport_opts
          DocsUI::Section('pgbus-only broadcast options (exclude: / visible_to:)') do
            DocsUI::Prose() do
              p do
                plain 'Because both transports share the identical '
                code { '::Turbo::StreamsChannel' }
                plain ' API, extra transport keywords are simply '
                em { 'forwarded' }
                plain ' to the stream. On Action Cable they are accepted and '
                strong { 'ignored' }
                plain ' (it has no per-connection routing); with pgbus they reach the ' \
                      'dispatcher:'
              end
              ul do
                li do
                  code { 'exclude:' }
                  plain ' — the actor\'s '
                  code { 'reactive_connection_id' }
                  plain '. Skips delivery to that one connection so the actor (who already ' \
                        'got the action\'s HTTP response) never gets a duplicate echo.'
                end
                li do
                  code { 'visible_to:' }
                  plain ' — scopes a broadcast to a subset of subscribers on the stream.'
                end
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # Under pgbus these reach the dispatcher; under Action Cable they no-op.
              Todos::Item.broadcast_to(
                @list, :todos,
                append: todo,
                target: dom_id(@list, :todos),
                exclude: reactive_connection_id # actor already has the HTTP response
              )
            RUBY
          end
        end

        def observability
          DocsUI::Section('Same observability on either transport') do
            DocsUI::Prose() do
              p do
                plain 'Each '
                code { 'broadcast_to' }
                plain ' call wraps its body in a '
                code { 'broadcast.phlex_reactive' }
                plain ' notification that fires on '
                strong { 'both' }
                plain ' Action Cable AND pgbus — the event wraps the class-method body, ' \
                      'which is identical on either transport. So an APM sees the same ' \
                      'broadcast fan-out (component name, stream action, streamables count — ' \
                      'never the model or state) no matter which transport you run.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              ActiveSupport::Notifications.subscribe("broadcast.phlex_reactive") do |*args|
                event = ActiveSupport::Notifications::Event.new(*args)
                MyAPM.record("reactive.broadcast", event.duration,
                  component: event.payload[:component],
                  stream_action: event.payload[:stream_action])
              end
            RUBY
          end
        end
      end
    end
  end
end
