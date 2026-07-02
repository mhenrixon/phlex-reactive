# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # The payment-split rebalancer — the example that makes issues #64–#67
      # concrete: model-scoped bracketed params (#67), a disabled computed field
      # the action still reads (#66), siblings auto-collected at dispatch (#65),
      # and a record used for identity/auth only while the action computes over
      # live, unsaved values (#64).
      class ExamplePaymentSplit < DocsUI::Page
        title 'Example: live payment split (sum-to-total rebalancer)'
        eyebrow 'Examples'

        def lead
          'Three amounts must always add up to a total. Editing one rebalances ' \
            'the others server-side — the pattern behind a live invoice split, a ' \
            'budget allocator, or any “these fields must sum” form.'
        end

        def content
          what
          component
          schema
          disabled_field
          transient
          notes
        end

        private

        def what
          DocsUI::Section('What it demonstrates') do
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Auto-collected siblings' }
                  plain ' — editing one field fires one action that receives the '
                  plain 'current value of every field of the reactive root, read at dispatch time.'
                end
                li do
                  strong { 'Model-scoped (bracketed) params' }
                  plain ' — the inputs are named '
                  code { 'split[allowance]' }
                  plain ', so the action schema nests under '
                  code { 'split:' }
                  plain ' to match.'
                end
                li do
                  strong { 'A disabled computed field' }
                  plain ' — the '
                  code { 'total' }
                  plain ' is disabled yet still collected and read (unlike a native form submit).'
                end
                li do
                  strong { 'Transient compute, no persist' }
                  plain ' — the action recomputes and re-renders in place; nothing is saved or broadcast.'
                end
              end
            end
          end
        end

        def component
          DocsUI::Section('The component') do
            DocsUI::Code(component_source, lexer: :ruby, filename: 'app/components/payment_split.rb')
          end
        end

        def schema
          DocsUI::Section('The nested schema mirrors the field names (#67)') do
            DocsUI::Prose() do
              p do
                plain 'A standard '
                code { 'Form(model: @invoice)' }
                plain ' names its inputs '
                code { 'invoice[amount]' }
                plain '. The client posts those names verbatim and the endpoint '
                plain 'bracket-expands them before matching your schema, so the schema must '
                strong { 'nest' }
                plain ' to match:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # ✅ nested — matches the bracketed field names
              action :rebalance, params: { split: { allowance: :integer, cash: :integer,
                                                     leasing: :integer, total: :integer } }

              # ❌ flat — matches NOTHING; the action silently gets its keyword defaults
              action :rebalance, params: { allowance: :integer, cash: :integer }
            RUBY
            DocsUI::Callout(:warning, title: 'A flat schema drops bracketed names silently') do
              plain 'There is no error — the top-level key after expansion is '
              code { 'split' }
              plain ', so a flat '
              code { 'allowance:' }
              plain ' key never matches and the action runs with defaults.'
            end
          end
        end

        def disabled_field
          DocsUI::Section('The total is disabled — and still read (#66)') do
            DocsUI::Prose() do
              p do
                plain 'Reactive field collection includes '
                code { 'disabled' }
                plain ' controls, deliberately unlike a native '
                code { '<form>' }
                plain ' submit. That is what lets a read-only computed field (here the '
                code { 'total' }
                plain ') travel to the action. Give the control no '
                code { 'name' }
                plain ', or make it '
                code { 'readonly' }
                plain ' instead of '
                code { 'disabled' }
                plain ', if you want native-form parity.'
              end
            end
          end
        end

        def transient
          DocsUI::Section('Record for auth, compute over live values (#64)') do
            DocsUI::Prose() do
              p do
                plain 'This demo is state-backed for simplicity. In a real app, swap '
                code { 'reactive_state' }
                plain ' for '
                code { 'reactive_record :invoice' }
                plain ' and authorize the row — the record is identity + authorization '
                plain 'only, while the action computes over the collected params and returns a '
                plain 'partial update, persisting nothing:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              reactive_record :invoice   # identity + auth ONLY
              action :rebalance, params: { split: { allowance: :integer, cash: :integer,
                                                     leasing: :integer, total: :integer } }

              def rebalance(split:)
                authorize! @invoice, :update?          # identity is not permission
                reconcile(split)                       # pure compute over the live fields
                reply.morph                            # re-render in place — no persist, no broadcast
              end
            RUBY
            DocsUI::Callout(:tip) do
              plain 'Deliberately no broadcast — peer tabs may have their own in-flight edits '
              plain 'that must not be clobbered. Broadcasting is always opt-in.'
            end
          end
        end

        def notes
          DocsUI::Section('Notes') do
            DocsUI::Prose() do
              ul do
                li do
                  code { 'reply.morph' }
                  plain ' re-renders through Idiomorph, so the field you are editing keeps its '
                  plain 'caret while the peers update to their reconciled numbers.'
                end
                li do
                  plain 'The '
                  code { 'changed:' }
                  plain ' param (an explicit '
                  code { 'on(:rebalance, changed: field)' }
                  plain ') tells the server which field was edited — explicit params ride alongside collected fields.'
                end
                li do
                  plain 'The rebalance is pure Ruby over the params — the same shape works whether '
                  plain 'the numbers come from signed state or a re-found record.'
                end
              end
            end
          end
        end

        def component_source
          <<~RUBY
            # app/components/payment_split.rb
            class PaymentSplit < ApplicationComponent
              include Phlex::Reactive::Component

              FIELDS = %i[allowance cash leasing].freeze

              reactive_state :allowance, :cash, :leasing, :total
              action :rebalance, params: {
                changed: :string,
                split: { allowance: :integer, cash: :integer, leasing: :integer, total: :integer }
              }

              def id = "payment-split"

              # `split` is the bracket-expanded, coerced inner hash; `total` rides in
              # it even though its field is disabled. Recompute and morph in place.
              def rebalance(changed:, split:)
                apply(split)
                reconcile(changed.to_sym)
                reply.morph                    # no persist, no broadcast
              end

              def view_template
                div(**reactive_root) do
                  FIELDS.each do |field|
                    # change-triggered; the field name is bracketed so it nests under split:
                    input(**mix(on(:rebalance, event: "change", changed: field.to_s),
                                type: "number", name: "split[\#{field}]", value: send(field), min: 0))
                  end
                  # disabled, but still collected + read by the action (#66)
                  input(type: "number", name: "split[total]", value: @total, disabled: true)
                end
              end
            end
          RUBY
        end
      end
    end
  end
end
