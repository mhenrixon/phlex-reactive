# frozen_string_literal: true

module Phlex
  module Reactive
    module Component
      # The class-level declaration DSL (issue #115): the five registries a
      # component declares itself through — reactive_record, reactive_state,
      # action, reactive_collection, reactive_compute — their public readers,
      # and from_identity (rebuilding an instance from a verified identity
      # payload). Every registry resolves through Component::Registry, so all
      # five share ONE inheritance semantic: resolve through the superclass at
      # read time, memoized per class against the registry generation.
      #
      # The readers are PUBLIC API — the action endpoint (reactive_action/
      # reactive_action?/reactive_actions), Response (reactive_collection_def),
      # Streamable's default #id (reactive_record_key), doctor, and the test
      # helpers all dispatch through them. They keep their exact signatures
      # forever; new reader forms (reactive_compute_def) are added alongside,
      # never instead.
      module DSL
        extend ActiveSupport::Concern

        class_methods do
          # Declare the ActiveRecord (GlobalID-able) record this component is
          # rebuilt from. The signed token carries its GlobalID; the server
          # re-finds it on each action. State lives in the DB.
          def reactive_record(name)
            Registry.write_scalar(self, :record_key, name.to_sym)
          end

          # The nearest declared record key up the ancestry, or nil. Resolved
          # through Registry (issue #115) — the same always-fresh semantics the
          # pre-#115 live superclass walk had, now memoized against the registry
          # generation like every other registry.
          def reactive_record_key
            Registry.resolve_scalar(self, :record_key, :reactive_record_key)
          end

          # Opt into signed STATE for record-less components only.
          #   reactive_state :count, :open
          def reactive_state(*names)
            Registry.append(self, :state_keys, names.map(&:to_sym))
          end

          # Ancestors' keys first, own appended — declaration order. Resolved
          # through Registry at read time (issue #115), so a parent's later
          # reactive_state is visible here and in the identity fast path (the
          # write sweeps the memoized ivar pairs family-wide).
          def reactive_state_keys
            Registry.resolve_list(self, :state_keys, :reactive_state_keys)
          end

          # Declare a client-invokable action with an optional param schema.
          #   action :increment
          #   action :rename, params: { title: :string }
          #
          # Param types are coerced server-side; anything not in the schema is
          # dropped before reaching your method (no mass assignment):
          #   * Scalars — :string (default), :integer, :float, :boolean
          #   * Array of scalar — wrap the type in an array: [:integer]
          #   * Array of hash (Rails nested attributes) — wrap a hash schema:
          #       action :save, params: {
          #         date: :string,
          #         bank_account_ids: [:integer],
          #         invoice_items_attributes: [
          #           { id: :integer, quantity: :float, price: :float, _destroy: :boolean }
          #         ]
          #       }
          # Array params accept BOTH a JSON array and a Rails-style index hash
          # ({ "0" => ..., "1" => ... }), so a fields_for collection works either way.
          def action(name, params: {})
            Registry.write_entry(
              self, :actions, name.to_sym,
              Action.new(name: name.to_sym, params: params, schema: Phlex::Reactive::ParamSchema.compile(params))
            )
          end

          # The full declared-action registry, ancestors included — the
          # default-deny source of truth the endpoint dispatches against.
          # Resolved through Registry at read time (issue #115): a parent action
          # declared after a subclass was first read is no longer silently
          # invisible to the subclass (the pre-#115 snapshot-dup divergence).
          def reactive_actions
            Registry.resolve_hash(self, :actions, :reactive_actions)
          end

          def reactive_action(name)
            reactive_actions[name.to_sym]
          end

          def reactive_action?(name)
            reactive_actions.key?(name.to_sym)
          end

          # Declare an add/remove-row collection (issue #35) — the list contract
          # in one place, so actions append/prepend/remove a row WITHOUT
          # re-deriving the container id, count, and empty-state in every action:
          #
          #   reactive_collection :items,
          #     item: ItemRowComponent,    # the per-row Streamable component
          #     container: "items-list",   # the DOM id rows live in
          #     count: "items-count",      # optional companion id (the size badge)
          #     empty: ItemsEmptyComponent, # optional empty-state component
          #     size: -> { @record.items.size } # resolves the live size
          #
          # An action then governs the reply with one call:
          #   reply.append(:items, item)   # row append + count + clear empty-state
          #   reply.remove(:items, id)     # row remove + count + restore empty-state
          #
          # count/empty/size are optional: a list with just rows omits them and the
          # corresponding stream isn't emitted. See Phlex::Reactive::Reply and the
          # README "Reactive collections" section.
          def reactive_collection(name, item:, container:, count: nil, empty: nil, size: nil)
            Registry.write_entry(
              self, :collections, name.to_sym,
              CollectionDefinition.new(name: name.to_sym, item:, container:, count:, empty:, size:)
            )
          end

          def reactive_collections
            Registry.resolve_hash(self, :collections, :reactive_collections)
          end

          def reactive_collection_def(name)
            reactive_collections[name.to_sym]
          end

          def reactive_collection?(name)
            reactive_collections.key?(name.to_sym)
          end

          # Declare a client-side computation, OR (called with just a name) read
          # one back. Dual-purpose so a component reads `reactive_compute :split,
          # inputs: …, outputs: …` and the endpoint/helpers read
          # `reactive_compute(:split)` — mirroring how `on`/`reactive_field` keep a
          # tight surface. `reducer:` defaults to the compute name.
          #
          #   reactive_compute :payment_split,
          #     inputs: %i[allowance cash leasing total],  # fields the JS reducer reads
          #     outputs: %i[allowance cash leasing]        # fields it writes (no round trip)
          #
          # `inputs:` also takes a HASH to TYPE each input (issue #104): a :number is
          # coerced through Number on the client (the array-form default), a :string
          # is read raw — so a live text preview reads real text, not NaN→0:
          #
          #   reactive_compute :preview,
          #     inputs: { title: :string, qty: :number },
          #     outputs: %i[title_preview char_count]
          #
          # An output with no matching form field writes to its reactive_text(:name)
          # node (textContent); a declared input also mirrors into its own text node
          # with no reducer. The array form's wire stays byte-identical.
          #
          # Register the matching JS once at boot. The reducer's signature is
          # (values, meta) — values is { inputName: Number } over the declared
          # inputs; meta is { changed }, the name of the declared input the
          # triggering event edited (null on a direct call or an unowned/
          # undeclared target). A one-argument reducer keeps working (it just
          # ignores meta); `changed` is what lets ONE reducer express a
          # multi-way/mutual rebalance (issue #75) — branch on the edited field.
          # Because an output write dispatches a real `input` event (issue #76),
          # a branching reducer must be CONVERGENT — the re-entrant pass must
          # recompute the values already written so the change guard settles it
          # (see the header of app/javascript/phlex/reactive/compute.js).
          #
          #   import { setComputeReducer } from "phlex/reactive/compute"
          #   setComputeReducer("payment_split", ({ allowance, cash, leasing, total }, { changed }) => ({ … }))
          def reactive_compute(name, inputs: nil, outputs: nil, reducer: nil)
            return reactive_compute_def(name) if inputs.nil? && outputs.nil?

            input_names, input_types = normalize_compute_inputs(inputs)
            Registry.write_entry(
              self, :computes, name.to_sym,
              ComputeDefinition.new(
                name: name.to_sym, inputs: input_names, input_types:,
                outputs: Array(outputs).map(&:to_sym), reducer: (reducer || name).to_s
              )
            )
          end

          def reactive_computes
            Registry.resolve_hash(self, :computes, :reactive_computes)
          end

          # Fetch one compute definition — the reader form matching
          # reactive_collection_def (issue #115). The bare reactive_compute(name)
          # getter above is a PERMANENT documented alias (it shipped in the same
          # minor series, #73); both stay, no deprecation.
          def reactive_compute_def(name)
            reactive_computes[name.to_sym]
          end

          def reactive_compute?(name)
            reactive_computes.key?(name.to_sym)
          end

          # Split the `inputs:` argument into [ordered names, types-or-nil] (issue
          # #104). A HASH ({ title: :string, qty: :number }) yields typed inputs —
          # the ordered keys plus a symbolized name→type map. Anything else (an
          # array, a bare symbol) is the UNTYPED form — ordered names and nil types,
          # so the array-form wire stays byte-identical and the client keeps its
          # numeric coercion. Named after the shape it normalizes.
          def normalize_compute_inputs(inputs)
            if inputs.is_a?(Hash)
              names = inputs.keys.map(&:to_sym)
              types = inputs.transform_keys(&:to_sym).transform_values(&:to_sym)
              [names, types]
            else
              [Array(inputs).map(&:to_sym), nil]
            end
          end

          # Rebuild a component instance from a verified identity payload. Called
          # by the action endpoint after the token signature is verified.
          #
          # A component may carry a record (re-found via GlobalID), signed state
          # (instance vars listed in reactive_state), or BOTH (the inline_edit
          # pattern: a record plus "which field / what mode"). We assemble the
          # init kwargs from whichever identity pieces are declared.
          def from_identity(payload)
            kwargs = {}

            if reactive_record_key
              record = GlobalID::Locator.locate(payload.fetch("gid"))
              raise(ActiveRecord::RecordNotFound, "reactive record missing") unless record

              kwargs[reactive_record_key] = record
            end

            if reactive_state_keys.any?
              state = payload.fetch("s", {})
              reactive_state_keys.each do
                # Use key presence, not the value: a signed `nil` (nullable state)
                # must round-trip distinctly. Only a genuinely absent key falls
                # back to the component's initialize default; `false` and `nil`
                # both survive.
                next unless state.key?(it.to_s)

                kwargs[it] = state[it.to_s]
              end
            end

            new(**kwargs)
          end
        end
      end
    end
  end
end
