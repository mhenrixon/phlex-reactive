# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Architecture < DocsUI::Page
        title 'Architecture'
        eyebrow 'Guide'

        def lead
          'A component owns a stable DOM id. Everything — a click, a form change, ' \
            'a background broadcast — reduces to “render this component into that id.”'
        end

        def content
          mental_model
          layers
          identity
        end

        private

        def mental_model
          DocsUI::Section('The mental model') do
            DocsUI::Prose() do
              p do
                plain 'Client interactivity ('
                code { 'Component' }
                plain ') and server-pushed live updates ('
                code { 'Streamable' }
                plain ') converge on ONE re-render unit. A reactive component '
                plain 'self-targets by its stable '
                code { '#id' }
                plain ', so a click and a broadcast share the same destination.'
              end
            end
          end
        end

        def layers
          DocsUI::Section('The layers') do
            DocsUI::Prose() do
              ul do
                li { plain 'Client runtime — one generic Stimulus controller.' }
                li { plain 'Endpoint — verify token → run action → render the reply.' }
                li do
                  plain 'Component mixin — reactive_record/reactive_state, action, on, and on_client ' \
                        '(declared client-only DOM ops via the js builder — zero round trip). ' \
                        'Including it pulls in Streamable automatically (one include is enough).'
                end
                li do
                  plain 'Streamable mixin — #id, replace/append, broadcast_*_to. ' \
                        'Record-backed components default #id to dom_id(record).'
                end
              end
            end
          end
        end

        def identity
          DocsUI::Section('Signed identity, not state') do
            DocsUI::Prose() do
              p do
                plain 'The DOM holds a signed identity — a '
                code { 'MessageVerifier' }
                plain ' token, never raw state. Tampering fails verification.'
              end
            end
            DocsUI::Callout(:warning, title: 'Never trust client input') do
              plain 'The signature proves the token is ours, NOT that this user may act. Authorize inside the action.'
            end
            # Dogfood: a reactive modal shows what the token actually contains.
            render ReactiveModalComponent.new(modal: 'signed-identity', label: "What's in the token?")
          end
        end
      end
    end
  end
end
