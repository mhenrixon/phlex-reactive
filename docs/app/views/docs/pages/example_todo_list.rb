# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleTodoList < ::Docs::Page
        title 'Example: live todo list'
        eyebrow 'Examples'

        def lead
          'Per-row reactive components with add / toggle / rename / delete, broadcasting on change so the ' \
            'list stays in sync across tabs and users — the canonical “list of records” pattern.'
        end

        def content
          model
          row
          list
          what_you_get
          keyed_lists
        end

        private

        def model
          render ::Docs::Section.new('Model') do
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby)
              class Todo < ApplicationRecord
                belongs_to :list
                # Live cross-client sync over pgbus SSE — transactional, reconnect-safe.
                broadcasts_to ->(t) { [t.list, :todos] }, durable: true
              end
            RUBY
            render ::Docs::Prose.new do
              p do
                code { 'broadcasts_to' }
                plain ' here only fires Turbo’s default per-record broadcasts. We drive the precise UI updates '
                plain 'from the reactive actions below, which is clearer for a component-rendered list — so you '
                plain 'can also omit '
                code { 'broadcasts_to' }
                plain ' and broadcast explicitly (shown inline).'
              end
            end
          end
        end

        def row
          render ::Docs::Section.new('One row (record-backed, all the actions)') do
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby)
              class Todos::Item < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component

                reactive_record :todo
                action :toggle
                action :rename, params: { title: :string }
                action :destroy

                def initialize(todo:) = @todo = todo
                def id = dom_id(@todo)

                def toggle
                  authorize! @todo, :update?
                  @todo.toggle!(:done)
                  broadcast
                end

                def rename(title:)
                  authorize! @todo, :update?
                  @todo.update!(title: title)
                  broadcast
                end

                def destroy
                  authorize! @todo, :destroy?
                  list = @todo.list
                  @todo.destroy!
                  Todos::Item.broadcast_remove_to(list, :todos, model: @todo) # other tabs
                  reply.remove                                                 # this tab's element
                end

                def view_template
                  li(**reactive_root(class: ("done" if @todo.done?))) do
                    button(**on(:toggle)) { @todo.done? ? "✓" : "○" }
                    input(name: "title", value: @todo.title, **on(:rename, event: "change"))
                    button(**on(:destroy)) { "✕" }
                  end
                end

                private

                # Re-render this row into every other subscribed tab.
                def broadcast
                  Todos::Item.broadcast_replace_to(@todo.list, :todos, model: @todo)
                end
              end
            RUBY
            render ::Docs::Prose.new do
              p do
                code { 'destroy' }
                plain ' returns '
                code { 'reply.remove' }
                plain ', so the actor’s own row is removed (via the built-in '
                code { 'Streamable#to_stream_remove' }
                plain ' — no tombstone, no endpoint override) and '
                code { 'broadcast_remove_to' }
                plain ' removes it in every other tab.'
              end
            end
          end
        end

        def list
          render ::Docs::Section.new('The list + composer') do
            render ::Docs::Code.new(<<~RUBY, lexer: :ruby)
              class Todos::List < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component

                reactive_record :list
                action :add, params: { title: :string }

                def initialize(list:) = @list = list
                def id = dom_id(@list, :todos_panel)

                def add(title:)
                  authorize! @list, :update?
                  title = title.to_s.strip
                  return if title.blank?

                  todo = @list.todos.create!(title:)
                  Todos::Item.broadcast_append_to(@list, :todos, target: dom_id(@list, :todos), model: todo)
                end

                def view_template
                  div(**reactive_root) do
                    turbo_stream_from @list, :todos                       # subscribe to live updates

                    ul(id: dom_id(@list, :todos)) do
                      @list.todos.order(:created_at).each { |t| render Todos::Item.new(todo: t) }
                    end

                    div do
                      input(name: "title", placeholder: "New todo…", autocomplete: "off")
                      button(**on(:add)) { "Add" }
                    end
                  end
                end
              end
            RUBY
          end
        end

        def what_you_get
          render ::Docs::Section.new('What you get') do
            render ::Docs::Prose.new do
              ul do
                li do
                  plain 'Toggle, rename (on '
                  code { 'change' }
                  plain '), add, delete — all without a Stimulus controller or a '
                  code { '.turbo_stream.erb' }
                  plain '.'
                end
                li do
                  plain 'Every change broadcasts the affected '
                  strong { 'row' }
                  plain ' (not the whole list) over pgbus SSE, so other tabs/users update with a minimal payload.'
                end
                li do
                  code { 'dom_id(@todo)' }
                  plain ' is the single source of truth for the row’s identity: the morph target for actions '
                  plain 'AND broadcasts.'
                end
              end
            end
          end
        end

        def keyed_lists
          render ::Docs::Section.new('Keyed lists & morphing') do
            render ::Docs::Prose.new do
              p do
                plain 'Give each row a stable '
                code { 'id' }
                plain ' (here '
                code { 'dom_id(@todo)' }
                plain ') so idiomorph can match rows across renders — that preserves focus in the rename input '
                plain 'and avoids re-creating unchanged rows.'
              end
            end
            render ::Docs::Callout.new(:warning, title: 'Don’t render list items without a stable id') do
              plain 'Without a stable per-row id, idiomorph can’t key the rows: focus is lost in the rename ' \
                    'input and unchanged rows are needlessly re-created.'
            end
          end
        end
      end
    end
  end
end
