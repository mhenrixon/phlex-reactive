# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleCounter < ::Docs::Page
        title 'Example: counter (the smallest reactive component)'
        eyebrow 'Examples'

        def lead
          'A record-less counter — the minimal thing that demonstrates ' \
            'client → server → re-render. Use this to sanity-check your install.'
        end

        def content
          component
          rendering
          notes
        end

        private

        def component
          render ::Docs::Section.new('The component') do
            render ::Docs::Prose.new do
              p do
                plain 'Include both mixins, sign the count into the DOM with '
                code { 'reactive_state' }
                plain ', and declare the actions a click may invoke.'
              end
            end
            render ::Docs::Code.new(component_source, lexer: :ruby, filename: 'app/components/counter.rb')
          end
        end

        def rendering
          render ::Docs::Section.new('Render it anywhere') do
            render ::Docs::Code.new('render Counter.new(count: 0)', lexer: :ruby)
          end
        end

        def notes
          render ::Docs::Section.new('Notes') do
            render ::Docs::Prose.new do
              ul do
                li do
                  code { 'reactive_state :count' }
                  plain ' signs the count into the DOM token. On each action the server rebuilds '
                  code { 'Counter.new(count: <verified>)' }
                  plain ', runs the method, and re-renders. The new count is signed into the next token automatically.'
                end
                li do
                  code { 'on(:set, count: 0)' }
                  plain ' passes an explicit param. Explicit params win over any collected form fields.'
                end
                li do
                  strong { 'Concurrency is handled.' }
                  plain ' Click '
                  code { '+' }
                  plain ' five times fast and you get '
                  code { '5' }
                  plain ' — the client serializes requests per component and threads the fresh token through, '
                  plain "so rapid clicks don't clobber each other."
                end
              end
            end
            render ::Docs::Callout.new(:tip) do
              plain 'This is record-less on purpose. For anything backed by data, prefer '
              code { 'reactive_record' }
              plain ' so state lives in the DB.'
            end
          end
        end

        def component_source
          <<~RUBY
            # app/components/counter.rb
            class Counter < ApplicationComponent
              include Phlex::Reactive::Streamable
              include Phlex::Reactive::Component

              reactive_state :count                       # signed state (no DB row)
              action :increment
              action :decrement
              action :set, params: { count: :integer }    # action with a typed param

              def initialize(count: 0) = @count = count
              def id = "counter"

              def increment = @count += 1
              def decrement = @count -= 1
              def set(count:) = @count = count

              def view_template
                div(**reactive_root(class: "counter")) do
                  button(**on(:decrement)) { "−" }
                  span(class: "value") { @count }
                  button(**on(:increment)) { "+" }
                  button(**on(:set, count: 0)) { "reset" }   # explicit param via on(...)
                end
              end
            end
          RUBY
        end
      end
    end
  end
end
