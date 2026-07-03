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
          loading_states
          dirty_tracking
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
            DocsUI::Code(<<~'RUBY', lexer: :ruby, filename: 'app/components/fields/inline_edit.rb')
              class Fields::InlineEdit < ApplicationComponent
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

                def id = dom_id(@record, "inline_#{@attribute}")

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
                      # reactive_input(:value) binds the field to the `value:` param —
                      # no hand-written name: "value" to forget. The trigger stays on
                      # the button, so focusing the field can't dispatch and collapse
                      # edit mode. Enter still saves via a keydown.enter binding on the
                      # field; Escape cancels on the Cancel button. event: "keydown.*"
                      # is Stimulus's native keyboard filter, so each fires only on its
                      # key — no JS.
                      reactive_input(:value, value: current_value, autocomplete: "off",
                                     **on(:save, event: "keydown.enter"))
                      button(**on(:save, disable_with: "Saving…")) { "Save" }
                      button(**on(:cancel, event: "keydown.esc")) { "Cancel" }
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
                  strong { 'Enter saves, Escape cancels.' }
                  plain ' '
                  code { 'on(:save, event: "keydown.enter")' }
                  plain ' and '
                  code { 'on(:cancel, event: "keydown.esc")' }
                  plain ' bind each key to its own element — '
                  code { 'event:' }
                  plain ' passes Stimulus’s native keyboard filter straight through, so the trigger fires '
                  plain 'only on that key. (One action per element: keep the Enter-save on the input and '
                  plain 'the Escape-cancel on the Cancel button.)'
                end
                li do
                  strong { 'The display text is the click target.' }
                  plain ' '
                  code { 'span(**on(:edit))' }
                  plain ' turns the display text into the trigger. Add '
                  code { 'tabindex' }
                  plain ' if you need a11y on non-button triggers.'
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

        def loading_states
          DocsUI::Section('Loading state on Save') do
            DocsUI::Prose() do
              p do
                plain 'Between the click and the re-render, the Save button should show it is working — and a '
                plain 'mutating button should swallow a rapid double-click. '
                code { 'disable_with:' }
                plain ' does both: it disables the trigger and swaps its text while the action is in flight, '
                plain 'reverting when the round trip settles (success '
                em { 'or' }
                plain ' failure).'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # Shorthand — disable + text swap while `save` is pending:
              button(**on(:save, disable_with: "Saving…")) { "Save" }

              # Full form — disable + a loading class + a text swap:
              button(**on(:save, loading: { disable: true, class: "opacity-50", text: "Saving…" })) { "Save" }
            RUBY
            DocsUI::Prose() do
              p do
                plain 'Independent of any '
                code { 'loading:' }
                plain ' hint, '
                strong { 'every' }
                plain ' reactive round trip marks the DOM for the whole enqueue → settle window, so you can style '
                plain 'spinners and dimming with pure CSS: the trigger and root carry '
                code { 'data-reactive-busy="save"' }
                plain ', the root carries '
                code { 'aria-busy="true"' }
                plain ', and '
                code { 'busy_on(:save)' }
                plain ' marks any element inside the root so it toggles '
                code { 'data-reactive-busy' }
                plain ' only while '
                code { 'save' }
                plain ' is in flight — a scoped spinner with zero Ruby.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              button(**on(:save, disable_with: "Saving…")) { "Save" }
              span(**busy_on(:save), class: "spinner")
            RUBY
            DocsUI::Callout(:note) do
              plain 'The disable + text swap apply only at enqueue, never during a '
              code { 'debounce:' }
              plain ' quiet period — so a debounced live-as-you-type field (whose element '
              em { 'is' }
              plain ' the input) is never disabled mid-typing.'
            end
          end
        end

        def dirty_tracking
          DocsUI::Section('Dirty tracking — enable Save only when it changed') do
            DocsUI::Prose() do
              p do
                plain 'An inline editor should light up Save (or show an “Unsaved” badge) only once the value '
                plain 'actually changed, and can warn before you navigate away with edits pending — '
                strong { 'without shipping any client state' }
                plain '. The browser already holds the last server-rendered value: '
                code { 'input.defaultValue' }
                plain ' is the attribute from the last render, so '
                em { 'dirty = current ≠ default' }
                plain ' is read straight from the DOM — nothing to snapshot, nothing to sign.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def view_template
                span(**reactive_root(track_dirty: true, warn_unsaved: true)) do
                  if @editing
                    reactive_input(:value, value: current_value, dirty: true,
                                   autocomplete: "off", **on(:save, event: "keydown.enter"))
                    span(class: "unsaved-badge") { "Unsaved" }  # shown via [data-reactive-dirty]
                    button(**on(:save, disable_with: "Saving…")) { "Save" }
                    button(**on(:cancel, event: "keydown.esc")) { "Cancel" }
                  else
                    span(**on(:edit), class: "editable") { current_value.presence || "—" }
                  end
                end
              end
            RUBY
            DocsUI::Prose() do
              ul do
                li do
                  code { 'track_dirty: true' }
                  plain ' on the root re-scans every field it owns on change; '
                  code { 'dirty: true' }
                  plain ' on a '
                  code { 'reactive_field' }
                  plain '/'
                  code { 'reactive_input' }
                  plain ' opts that one field in. Each changed field gets '
                  code { 'data-reactive-dirty="true"' }
                  plain ' and the root gets '
                  code { 'data-reactive-dirty="<count>"' }
                  plain ' — absent at zero, so '
                  code { '[data-reactive-dirty]' }
                  plain ' matches only while the form is dirty.'
                end
                li do
                  code { 'warn_unsaved: true' }
                  plain ' arms a navigate-away guard (browser '
                  code { 'beforeunload' }
                  plain ' + Turbo '
                  code { 'turbo:before-visit' }
                  plain ') gated on the live dirty count — a clean form never blocks.'
                end
                li do
                  strong { 'Baselines reset on the server re-render.' }
                  plain ' A '
                  code { 'reply.morph' }
                  plain ' save renders the field with the saved value as its '
                  em { 'new' }
                  plain ' default, so the badge clears with no reload — the client re-scans after the morph writes '
                  plain 'the fresh '
                  code { 'default*' }
                  plain ' attributes.'
                end
              end
            end
            DocsUI::Code(<<~CSS, lexer: :css)
              /* You own the styling — phlex-reactive ships no CSS for these. */
              .unsaved-badge { display: none; }
              [data-reactive-dirty] .unsaved-badge { display: inline; }
              [data-reactive-dirty] button[data-testid="save"] { pointer-events: auto; opacity: 1; }
            CSS
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
                plain '). A string is escaped and wrapped in a level-carrying '
                code { '<div class="reactive-flash reactive-flash--error" data-reactive-flash-level="error">' }
                plain ' so errors and notices style differently; pass a Phlex component instead for '
                plain 'fully custom markup (rendered verbatim, no wrapper), or set '
                code { 'Phlex::Reactive.flash_component' }
                plain ' once to render every string flash through your own component ('
                code { 'new(level:, content:)' }
                plain ').'
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
              p do
                strong { 'Advance to the next field on save.' }
                plain ' Chain '
                code { '.js' }
                plain ' onto any reply to push client DOM ops that run '
                em { 'after' }
                plain ' the render, so a focus op sees the freshly morphed DOM — natural for a grid where Enter '
                plain 'should hop to the next cell:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def update(name:)
                authorize! @record, :update?
                @record.update!(name:) if name.present?
                # Morph in place (keep caret), THEN focus the next field:
                reply.morph.js(js.focus("[name=next_field]"))
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'When the morph target is a '
                em { 'sibling' }
                plain ' cell rather than the field you are typing in, prefer '
                code { 'reply.streams' }
                plain ' — it emits exactly the streams you name plus a tiny token-only refresh (no full-self '
                plain 'replace), so a neighbouring '
                code { '<input>' }
                plain ' the user is mid-typing in is never torn down while the total cell updates.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def update(quantity:, price:)
                @item.update!(quantity:, price:)
                reply.streams(Totals.update(@item))   # re-stream ONLY the total cell
              end
            RUBY
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
