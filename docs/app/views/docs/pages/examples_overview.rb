# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExamplesOverview < DocsUI::Page
        title 'Examples'
        eyebrow 'Examples'

        def lead
          'Concrete, copy-pasteable examples covering the common patterns. ' \
            'Each is a complete, working feature.'
        end

        def content
          examples
        end

        private

        def examples
          DocsUI::Section('The examples') do
            DocsUI::Prose() do
              p do
                plain 'Each example below is a complete, working feature you can copy and paste. '
                plain 'They build from the smallest reactive component up to record-backed actions, '
                plain 'live broadcasts, and declared-once collections.'
              end
              ul do
                example_item(
                  'example-counter', 'Counter'
                ) do
                  plain 'State-backed — the smallest reactive component.'
                end
                example_item('example-chat', 'Cross-tab chat') do
                  plain 'Record-backed action '
                  strong { 'and broadcast' }
                  plain ' → live cross-tab sync.'
                end
                example_item('example-todo-list', 'Live todo list') do
                  plain 'Per-row components; add / toggle / rename.'
                end
                example_item('example-inline-edit', 'Inline edit') do
                  plain 'Show ↔ edit mode toggle in one component.'
                end
                example_item('example-notifications', 'Notifications / badges') do
                  plain 'Pure broadcast (no client action).'
                end
                example_item('example-collections', 'Reactive collections') do
                  plain 'Add/remove rows + count + empty-state, declared once.'
                end
              end
            end
          end
        end

        def example_item(slug, label, &)
          li do
            a(href: doc_path(slug)) { label }
            plain ' — '
            yield
          end
        end
      end
    end
  end
end
