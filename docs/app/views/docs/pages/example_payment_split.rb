# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # The payment-split rebalancer — the example that makes issues #64–#67
      # concrete: model-scoped bracketed params (#67), a disabled computed field
      # the action still reads (#66), siblings auto-collected at dispatch (#65),
      # and a record used for identity/auth only while the action computes over
      # live, unsaved values (#64). It is ALSO the gem's canonical
      # reactive_compute example (#75/#104): the same sum-to-total rebalance runs
      # in-browser with no round trip, then the debounced POST reconciles.
      class ExamplePaymentSplit < DocsUI::Page
        title 'Example: live payment split (sum-to-total rebalancer)'
        eyebrow 'Examples'

        def lead
          'Three amounts must always add up to a total. Editing one rebalances ' \
            'the others — the pattern behind a live invoice split, a budget ' \
            'allocator, or any “these fields must sum” form. It comes in two ' \
            'flavors: a server round-trip that recomputes and morphs in place, ' \
            'and a client-side compute that rebalances INSTANTLY with the ' \
            'server reply reconciling behind it.'
        end

        def content
          try_live_compute
          two_variants
          what
          component
          schema
          disabled_field
          live_typing
          compute
          transient
          notes
        end

        private

        def try_live_compute
          DocsUI::Section('Try it — a client-side compute') do
            md <<~MD
              Before the payment-split walkthrough, here's the `reactive_compute` +
              `reactive_text` shape in its smallest form: a live post preview. Type
              in the field — the heading mirrors the title and the counter recomputes
              **in the browser with no round trip** (an `input->reactive#recompute`
              runs the `preview` JS reducer). Click **Save** and the server persists
              and re-renders, seeding the identical derived text — the one-math-two-
              sites contract `reactive_compute` exists to enforce.
            MD
            render Views::Examples::LiveExample.new(
              component: PostPreviewComponent.new(todo: preview_demo_todo),
              filename: 'app/components/post_preview_component.rb'
            )
          end
        end

        def two_variants
          DocsUI::Section('Two flavors of the same rebalance') do
            DocsUI::Prose() do
              p do
                plain 'The rebalance is one calculation — three amounts spill their '
                plain 'difference across each other so they always sum to the total. '
                plain 'Where that calculation runs is the choice:'
              end
              ul do
                li do
                  strong { 'Server round-trip' }
                  plain ' — every edit fires an action ('
                  code { 'on(:rebalance, event: "change")' }
                  plain '); the server recomputes and '
                  code { 'reply.morph' }
                  plain 's the reconciled numbers in place. One source of truth, no client math.'
                end
                li do
                  strong { 'Client-side compute' }
                  plain ' — '
                  code { 'reactive_compute' }
                  plain ' runs a JS reducer on '
                  code { 'input' }
                  plain ', writing the peers with no round trip, while a debounced POST '
                  plain 'reconciles from the server. The compute just paints first.'
                end
              end
              p do
                plain 'This page shows the server variant first (it is the simplest to '
                plain 'reason about), then the compute variant that makes it feel instant. '
                plain 'The math is identical — that lockstep is the whole contract.'
              end
            end
          end
        end

        def what
          DocsUI::Section('What the server variant demonstrates') do
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
          DocsUI::Section('The server-variant component') do
            DocsUI::Prose() do
              p do
                plain 'Each amount is a '
                code { 'change' }
                plain '-triggered '
                code { 'rebalance' }
                plain '. The bracketed '
                code { 'name:' }
                plain ' is one place a manual name beats the '
                code { 'reactive_field' }
                plain ' sugar — see the note below.'
              end
            end
            DocsUI::Code(component_source, lexer: :ruby, filename: 'app/components/payment_split.rb')
            DocsUI::Callout(:note, title: 'apply / reconcile are YOUR methods') do
              plain 'Neither is gem API. '
              code { 'apply' }
              plain ' assigns the collected split onto your state and '
              code { 'reconcile' }
              plain ' is your pure rebalance math (spill the difference into the peers). '
              plain 'The gem gives you '
              code { 'reply.morph' }
              plain '; the calculation is ordinary Ruby you write.'
            end
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
              p do
                plain 'The compute variant below adds a '
                code { 'remaining' }
                plain ' output with no matching field — the reducer writes it into a live '
                code { 'reactive_text' }
                plain ' node (text content, XSS-safe) with no round trip, so a derived '
                plain 'read-out never needs the server at all.'
              end
            end
          end
        end

        def live_typing
          DocsUI::Section('Live as you type: input + debounce') do
            DocsUI::Prose() do
              p do
                plain 'The component above triggers on '
                code { 'event: "change"' }
                plain ', which fires on blur/commit — the rebalance lands when you '
                plain 'leave the field. For a truly live feel, trigger on '
                code { 'input' }
                plain ' and debounce so it recomputes as the user types:'
              end
            end
            DocsUI::Code(<<~'RUBY', lexer: :ruby)
              # Recompute while typing, but coalesce the POSTs: one request 300ms
              # after the last keystroke, not one per character.
              input(**mix(on(:rebalance, event: "input", debounce: 300, changed: field.to_s),
                          type: "number", name: "split[#{field}]", value: send(field), min: 0))
            RUBY
            DocsUI::Prose() do
              p do
                plain 'Because the round-trip is now firing on every pause, show that it is '
                plain 'in flight. Every trigger and the root already carry '
                code { 'data-reactive-busy' }
                plain ' (and '
                code { 'aria-busy' }
                plain ') while a request is out — style them, or add a scoped '
                code { 'busy_on(:rebalance)' }
                plain ' spinner and a '
                code { 'disable_with:' }
                plain ' hint:'
              end
            end
            DocsUI::Code(<<~'RUBY', lexer: :ruby)
              # Scoped spinner: only lit while :rebalance is in flight.
              span(**busy_on(:rebalance), class: "loading loading-spinner loading-xs hidden")

              # Or a declarative per-trigger loading hint on the field itself.
              input(**mix(on(:rebalance, event: "input", debounce: 300, loading: { class: "opacity-50" }),
                          type: "number", name: "split[#{field}]", value: send(field)))
            RUBY
          end
        end

        def compute
          DocsUI::Section('Instant, no round trip: the client-side compute (#75/#104)') do
            DocsUI::Prose() do
              p do
                plain 'For a NEW, unsaved invoice the running total should feel instant. '
                code { 'reactive_compute' }
                plain ' declares a client-side reducer that runs on '
                code { 'input' }
                plain ' and writes the derived amounts straight into the DOM — no round '
                plain 'trip. When the component also carries '
                code { 'on(...)' }
                plain ', the debounced POST still fires and the server reply reconciles; '
                plain 'the compute just paints first.'
              end
            end
            DocsUI::Code(compute_source, lexer: :ruby, filename: 'app/components/payment_split.rb')
            DocsUI::Prose() do
              p do
                plain 'Register the reducer once at boot. Its signature is '
                code { '(values, { changed })' }
                plain '; branching on '
                code { 'changed' }
                plain ' is what makes a multi-way, mutual rebalance expressible as one reducer (#75):'
              end
            end
            DocsUI::Code(<<~JS, lexer: :javascript, filename: 'app/javascript/application.js')
              import { setComputeReducer } from "phlex/reactive/compute"

              // The JS twin of the Ruby rebalance — keep the two in lockstep.
              // The edited `allowance` keeps its value; cash absorbs the remainder;
              // an over-total edit caps allowance and zeros the peers. `remaining`
              // is a text-node output (no matching field) written straight to the DOM.
              setComputeReducer("payment_split", ({ allowance, total }) => {
                if (allowance >= total) return { allowance: total, cash: 0, leasing: 0, remaining: 0 }
                const cash = total - allowance
                return { allowance, cash, leasing: 0, remaining: total - allowance - cash }
              })
            JS
            DocsUI::Callout(:warning, title: 'Seed the same value the reducer would') do
              plain 'The server render must seed each output ('
              code { 'reactive_text(:remaining, "0")' }
              plain ', the field values) with the same derived number the reducer produces — '
              plain 'otherwise a later morph repaints stale text. That lockstep is the reconcile '
              plain 'contract the whole new-vs-persisted split relies on.'
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
                apply(split)                           # your own: assign the live fields
                reconcile(:allowance)                  # your own: pure rebalance math
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
                  plain ') tells the server which field was edited — explicit params ride alongside collected fields. '
                  plain 'The reducer gets the same name in its '
                  code { '{ changed }' }
                  plain ' meta.'
                end
                li do
                  plain 'The bracketed '
                  code { 'name: "split[allowance]"' }
                  plain ' is hand-written on purpose: '
                  code { 'reactive_field(:value)' }
                  plain ' binds a control to a flat param, but the model-scoped bracket '
                  plain 'is exactly the case where the manual '
                  code { 'name:' }
                  plain ' is clearer than the sugar.'
                end
                li do
                  plain 'The rebalance is pure Ruby over the params — the same shape works whether '
                  plain 'the numbers come from signed state, a re-found record, or the client reducer.'
                end
              end
            end
          end
        end

        # A dedicated demo record for the live compute preview, found-or-created so
        # repeated page renders reuse one row.
        def preview_demo_todo
          Todo.find_or_create_by!(title: 'Type here to preview')
        end

        def component_source
          <<~'RUBY'
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
              # it even though its field is disabled. `apply`/`reconcile` are YOUR
              # own methods (assign the fields, then spill the difference into the
              # peers) — the gem only hands you reply.morph.
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
                                type: "number", name: "split[#{field}]", value: send(field), min: 0))
                  end
                  # disabled, but still collected + read by the action (#66)
                  input(type: "number", name: "split[total]", value: @total, disabled: true)
                end
              end
            end
          RUBY
        end

        def compute_source
          <<~'RUBY'
            # app/components/payment_split.rb — the client-side compute variant
            class PaymentSplit < ApplicationComponent
              include Phlex::Reactive::Component

              FIELDS = %i[allowance cash leasing].freeze

              reactive_state :allowance, :cash, :leasing, :total
              action :rebalance, params: {
                split: { allowance: :integer, cash: :integer, leasing: :integer, total: :integer }
              }

              # Client-side reducer (registered in JS under this name). It reads the
              # named inputs and WRITES the outputs with no round trip — the debounced
              # POST reconciles afterwards from reply.morph.
              reactive_compute :payment_split,
                inputs:  %i[allowance cash leasing total],       # fields the JS reducer reads
                outputs: %i[allowance cash leasing remaining]    # 3 fields + one text node

              def id = "payment-split"

              def rebalance(split:)
                apply(split)                     # your own: assign the live fields
                reconcile(:allowance)            # your own: pure rebalance math
                reply.morph                      # server reconciles the client paint
              end

              def view_template
                # Spread reactive_compute_attrs ALONGSIDE reactive_root so the generic
                # controller finds the reducer and the named fields inside this root.
                div(**mix(reactive_root, reactive_compute_attrs(:payment_split))) do
                  FIELDS.each do |field|
                    # `input`-triggered + debounced: recompute on the client every
                    # keystroke, POST 300ms after the last one.
                    input(**mix(on(:rebalance, event: "input", debounce: 300),
                                type: "number", name: "split[#{field}]", value: send(field), min: 0))
                  end
                  # A live text output the reducer writes — no name, never POSTed.
                  # Seeded with the same value the reducer would produce.
                  span { plain "Remaining: " }
                  reactive_text(:remaining, "0")
                end
              end
            end
          RUBY
        end
      end
    end
  end
end
