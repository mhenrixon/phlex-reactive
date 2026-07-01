# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class TransportPgbus < DocsUI::Page
        title 'Transport: pgbus vs Action Cable'
        eyebrow 'Guide'

        def lead
          "phlex-reactive's client → server half is a plain HTTP POST. The server → " \
            'client half (broadcasts) rides on whatever transport turbo-rails is configured with.'
        end

        def content
          choices
          comparison
        end

        private

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
          DocsUI::Section('Why pgbus') do
            DocsUI::Prose() do
              ul do
                li do
                  plain 'Transactional broadcasts — deferred to after_commit; a rolled-back transaction emits nothing.'
                end
                li { plain 'Reconnect-safe — the client replays missed messages from the PGMQ archive.' }
                li { plain 'No render→subscribe race — broadcasts are watermarked and replayed.' }
              end
            end
            DocsUI::Callout(:tip) do
              plain 'No Redis, no Action Cable. One Postgres — and your phlex-reactive code is identical.'
            end
          end
        end
      end
    end
  end
end
