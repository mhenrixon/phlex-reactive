# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleInlineEdit < DocsUI::Page
        title 'Example: inline edit (show ↔ edit)'
        eyebrow 'Examples'

        def lead
          'The classic “click to edit a field in place” pattern — one component with two ' \
            'actions, instead of a Stimulus controller plus three routes and partials.'
        end

        def content
          the_component
          rendering
          notes
          validation_error
          live_as_you_type
          broadcasting
        end

        private

        def the_component
          DocsUI::Section('The component') do
            DocsUI::Prose() do
              p do
                plain 'In plain Hotwire this is a Stimulus controller plus three routes ('
                code { 'inline_edit' }
                plain ', '
                code { 'inline_update' }
                plain ', '
                code { 'inline_cancel' }
                plain ') and partials. Here it is one component with two actions.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/fields/inline_edit.rb')
              class Fields::InlineEdit < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component

                reactive_record :record
                reactive_state :attribute, :editing     # which field, and the mode

                action :edit
                action :cancel
                action :save, params: { value: :string }

                def initialize(record:, attribute:, editing: false)
                  @record = record
                  @attribute = attribute.to_sym
                  @editing = editing
                end

                def id = dom_id(@record, "inline_\#{@attribute}")

                def edit   = @editing = true
                def cancel = @editing = false

                def save(value:)
                  authorize! @record, :update?
                  @record.update!(@attribute => value)
                  @editing = false
                end

                def view_template
                  span(**reactive_root) do
                    if @editing
                      input(name: "value", value: current_value, autocomplete: "off")
                      button(**on(:save)) { "Save" }
                      button(**on(:cancel)) { "Cancel" }
                    else
                      span(**on(:edit), class: "editable") { current_value.presence || "—" }
                    end
                  end
                end

                private

                def current_value = @record.public_send(@attribute)
              end
            RUBY
          end
        end

        def rendering
          DocsUI::Section('Render it for any field') do
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              render Fields::InlineEdit.new(record: @user, attribute: :name)
              render Fields::InlineEdit.new(record: @user, attribute: :email)
            RUBY
          end
        end

        def notes
          DocsUI::Section('Notes') do
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Two pieces of identity' }
                  plain ': '
                  code { 'reactive_record :record' }
                  plain ' (the row, re-found via GlobalID) and '
                  code { 'reactive_state :attribute, :editing' }
                  plain ' (which field, what mode). Both are signed; the client cannot switch '
                  code { '@attribute' }
                  plain ' to a column it should not edit because the value is signed into the token.'
                end
                li do
                  strong { 'Mode is server state.' }
                  plain ' '
                  code { 'edit' }
                  plain '/'
                  code { 'cancel' }
                  plain '/'
                  code { 'save' }
                  plain ' flip '
                  code { '@editing' }
                  plain ' and re-render the same element — no separate “edit” route or partial.'
                end
                li do
                  strong { 'Authorize on save.' }
                  plain ' '
                  code { 'edit' }
                  plain '/'
                  code { 'cancel' }
                  plain ' are harmless view toggles; '
                  code { 'save' }
                  plain ' mutates, so it authorizes.'
                end
                li do
                  strong { 'The display text is the click target.' }
                  plain ' '
                  code { 'span(**on(:edit))' }
                  plain ' turns the display text into the trigger. Add '
                  code { 'tabindex' }
                  plain ' / keyboard handling if you need a11y on non-button triggers.'
                end
                li do
                  strong { 'Rich-text fields work too.' }
                  plain ' A named '
                  code { 'lexxy-editor' }
                  plain ', '
                  code { 'trix-editor' }
                  plain ', or '
                  code { '[contenteditable]' }
                  plain ' is auto-collected on submit alongside plain inputs — so '
                  code { 'save' }
                  plain ' receives its value, not a blank.'
                end
              end
            end
          end
        end

        def validation_error
          DocsUI::Section('Surfacing a validation error') do
            DocsUI::Prose() do
              p do
                code { 'save' }
                plain ' above uses '
                code { 'update!' }
                plain ', which raises on invalid input. To show the error instead, use non-bang '
                code { 'update' }
                plain ' and return '
                code { 'reply' }
                plain ' with a flash.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def save(value:)
                authorize! @record, :update?
                if @record.update(@attribute => value)
                  @editing = false
                  reply.replace
                else
                  reply.replace.flash(:error, @record.errors.full_messages.to_sentence)
                end
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'The flash '
                code { 'content' }
                plain ' is supplied explicitly (off-request — no Rails '
                code { 'flash' }
                plain ') and appends into '
                code { 'Phlex::Reactive.flash_target' }
                plain ' (default '
                code { '<div id="flash">' }
                plain '); pass a Phlex component instead of a string for rich markup.'
              end
            end
          end
        end

        def live_as_you_type
          DocsUI::Section('Live-as-you-type (a spreadsheet-like grid)') do
            DocsUI::Prose() do
              p do
                plain 'For per-field editing where a '
                strong { 'debounced save fires while the user is still typing or tabbing' }
                plain ', a plain '
                code { 'reply.replace' }
                plain ' is wrong: it is an outerHTML swap that destroys the '
                code { '<input>' }
                plain ' you are typing in — focus and the in-progress value vanish. Return '
                code { 'reply.morph' }
                plain ' instead. It emits '
                code { '<turbo-stream action="replace" method="morph">' }
                plain ', so Turbo 8’s bundled Idiomorph morphs the subtree in place — the focused field '
                plain 'and its caret survive the save.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              action :update, params: { name: :string }

              def update(name:)
                authorize! @record, :update?
                @record.update!(name:) if name.present?
                reply.morph   # morph in place — keep focus + caret. The action is named
                              # `update`, but `reply.morph` is unambiguous (the verb is on reply).
              end

              def view_template
                div(**reactive_root) do
                  # The field both holds the value AND triggers the debounced save.
                  input(**mix(on(:update, event: "input", debounce: 300),
                    name: "name", value: @record.name))
                end
              end
            RUBY
            DocsUI::Prose() do
              p do
                code { 'reply.replace(morph: true)' }
                plain ' is the same thing via the opt-in flag; the morphed root still carries a '
                plain 'fresh signed token, so the next edit verifies.'
              end
            end
          end
        end

        def broadcasting
          DocsUI::Section('Want it to update other viewers too?') do
            DocsUI::Prose() do
              p { plain 'Broadcast on save.' }
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def save(value:)
                authorize! @record, :update?
                @record.update!(@attribute => value)
                @editing = false
                Fields::InlineEdit.broadcast_replace_to(
                  @record, model: @record, attribute: @attribute
                )
              end
            RUBY
            DocsUI::Callout(:tip) do
              plain 'Now everyone viewing that record sees the new value land in place.'
            end
          end
        end
      end
    end
  end
end
