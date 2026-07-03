# frozen_string_literal: true

module Phlex
  module Reactive
    # Component turns a self-contained Phlex component into a Livewire-style
    # reactive unit: declare actions in Ruby, and the generic `reactive`
    # Stimulus controller wires clicks/inputs to an HTTP round trip that
    # re-renders the component and applies it back into the DOM (a plain replace
    # by default; return Response.morph(self) to morph in place and keep the
    # focused input — issue #28). No per-feature Stimulus controllers, no
    # hand-picked Turbo targets.
    #
    # Including Component pulls in Phlex::Reactive::Streamable automatically
    # (Concern dependency — Streamable lands on the base first, exactly the old
    # manual order), so ONE include is enough. The legacy explicit double
    # include remains a harmless no-op.
    #
    # === Security model (the decisive design choice) ===
    # We do NOT ship component STATE to the browser (no snapshot). The DOM
    # carries a signed IDENTITY:
    #
    #   * Record-backed (the common case): reactive_record :todo signs the
    #     record's GlobalID. The server re-finds it via GlobalID — the client
    #     can neither forge the component class nor swap the record. State =
    #     the database.
    #   * State-backed (record-less, e.g. a counter): reactive_state :count
    #     signs the listed instance variables. Use when there is genuinely no
    #     record to re-find.
    #   * Both (the inline_edit pattern): reactive_record :record plus
    #     reactive_state :attribute, :editing signs the record's GlobalID AND
    #     the transient mode in one token, so "which field / what mode" survives
    #     every action round trip and stays tamper-proof.
    #
    # Actions are DEFAULT-DENY: only methods declared with `action :name` may be
    # invoked. The signature proves the token is ours, NOT that this user may
    # act — your action must still authorize the record. Action params pass
    # through a declared schema; nothing else reaches the method.
    #
    # Usage (record-backed — #id defaults to dom_id(@todo), issue #81):
    #   class Todos::Item < ApplicationComponent
    #     include Phlex::Reactive::Component
    #
    #     reactive_record :todo
    #     action :toggle
    #     action :rename, params: { title: :string }
    #
    #     def initialize(todo:) = @todo = todo
    #
    #     def toggle  = (authorize!(@todo, :update?); @todo.toggle!(:done))
    #     def rename(title:) = (authorize!(@todo, :update?); @todo.update!(title:))
    #
    #     def view_template
    #       li(id:, **reactive_attrs) do
    #         button(**on(:toggle)) { @todo.done? ? "✓" : "○" }
    #         span { @todo.title }
    #       end
    #     end
    #   end
    module Component
      extend ActiveSupport::Concern
      include Phlex::Reactive::Streamable

      # A declared, client-invokable action and its param schema.
      Action = Data.define(:name, :params)

      # A declared client-side computation (data binding). `inputs`/`outputs` are
      # the action-param names of the fields the reducer reads/writes; `reducer`
      # is the key a JS function is registered under (Reactive.compute(key, fn)).
      # The generic controller runs the reducer on `input` — writing outputs with
      # NO round trip — then the debounced POST reconciles from the server reply.
      ComputeDefinition = Data.define(:name, :inputs, :outputs, :reducer)

      # A declared add/remove-row collection (issue #35): the list contract tied
      # into one unit — the per-row item component, the container DOM id rows
      # live in, an optional companion count id, an optional empty-state
      # component, and a size resolver (a proc evaluated against the container
      # instance) used to re-render the count and toggle the empty-state at the
      # 0<->1 boundary. count/empty/size are nil when not declared, and the
      # corresponding stream is simply omitted — so a list with just rows still
      # works.
      CollectionDefinition = Data.define(:name, :item, :container, :count, :empty, :size) do
        # The collection's current size, evaluated against the bound container
        # instance (instance_exec so the proc reads the component's ivars /
        # association). nil when no resolver was declared — callers skip the
        # count/empty streams that need a number.
        def size_for(component)
          size && component.instance_exec(&size)
        end
      end

      class_methods do
        # Declare the ActiveRecord (GlobalID-able) record this component is
        # rebuilt from. The signed token carries its GlobalID; the server
        # re-finds it on each action. State lives in the DB.
        def reactive_record(name)
          @reactive_record_key = name.to_sym
          remove_instance_variable(:@reactive_record_ivar) if defined?(@reactive_record_ivar)
        end

        def reactive_record_key
          return @reactive_record_key if defined?(@reactive_record_key)

          superclass.respond_to?(:reactive_record_key) ? superclass.reactive_record_key : nil
        end

        # Opt into signed STATE for record-less components only.
        #   reactive_state :count, :open
        def reactive_state(*names)
          reactive_state_keys.concat(names.map(&:to_sym))
          @reactive_state_ivars = nil # rebuild the cached [key, ivar] pairs
        end

        def reactive_state_keys
          @reactive_state_keys ||= (superclass.respond_to?(:reactive_state_keys) ? superclass.reactive_state_keys.dup : [])
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
          reactive_actions[name.to_sym] = Action.new(name: name.to_sym, params: params)
        end

        def reactive_actions
          @reactive_actions ||= (superclass.respond_to?(:reactive_actions) ? superclass.reactive_actions.dup : {})
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
          reactive_collections[name.to_sym] =
            CollectionDefinition.new(name: name.to_sym, item:, container:, count:, empty:, size:)
        end

        def reactive_collections
          @reactive_collections ||= superclass.respond_to?(:reactive_collections) ? superclass.reactive_collections.dup : {}
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
          return reactive_computes[name.to_sym] if inputs.nil? && outputs.nil?

          reactive_computes[name.to_sym] = ComputeDefinition.new(
            name: name.to_sym, inputs: Array(inputs).map(&:to_sym),
            outputs: Array(outputs).map(&:to_sym), reducer: (reducer || name).to_s
          )
        end

        def reactive_computes
          @reactive_computes ||= superclass.respond_to?(:reactive_computes) ? superclass.reactive_computes.dup : {}
        end

        def reactive_compute?(name)
          reactive_computes.key?(name.to_sym)
        end

        # The record's instance-variable symbol (e.g. :@todo), computed once.
        # reactive_token reads it on every render; interpolating :"@#{key}" each
        # time would allocate a symbol per render. Nil when record-less. Memoized
        # per class; reset alongside reactive_record so it can't go stale.
        def reactive_record_ivar
          return @reactive_record_ivar if defined?(@reactive_record_ivar)

          @reactive_record_ivar = reactive_record_key ? :"@#{reactive_record_key}" : nil
        end

        # [string_key, ivar_symbol] pairs for the signed state, computed once.
        # reactive_token walks these every render; precomputing the "count"/:@count
        # forms avoids a String + Symbol allocation per key per render. Memoized
        # per class; reset when reactive_state adds a key.
        def reactive_state_ivars
          @reactive_state_ivars ||= reactive_state_keys.map { [it.to_s, :"@#{it}"] }
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

      # The acting client's SSE connection id during the current action (nil
      # outside an action, or when the client isn't subscribed to a stream).
      # Pass it as `exclude:` when broadcasting from an action so the actor
      # doesn't receive the echo of its own change — it already gets the
      # action's HTTP response:
      #
      #   def send_message(body:)
      #     msg = ChatMessage.create!(room: @room, body:)
      #     ChatMessage::Item.broadcast_append_to("chat", @room,
      #       target: "messages", model: msg, exclude: reactive_connection_id)
      #   end
      def reactive_connection_id
        Phlex::Reactive.current_connection_id
      end

      # Subject-bound reply builder — the preferred way to control an action's
      # reply. `reply.replace.flash(:error, msg)` reads cleaner than
      # `Phlex::Reactive::Response.replace(self).flash(:error, msg)`: the
      # component is the implicit subject (no `self` to thread) and there's no
      # constant to qualify (reply is a method, so a namespaced component needs
      # no `Response = …` alias). It returns the same immutable Response the
      # endpoint reads, so chaining and the legacy return-value contract are
      # unchanged. See Phlex::Reactive::Reply.
      #
      #   def archive       = reply.remove
      #   def go_home       = reply.redirect("/todos")
      #   def update(name:) = (@account.update!(name:); reply.morph)
      def reply
        Phlex::Reactive::Reply.new(self)
      end

      # An empty client-side op chain (issue #95) — the starting point for
      # on_client's DOM commands, mirroring how `reply` starts a Response chain:
      #   button(**on_client(:click, js.toggle("#menu"))) { "Menu" }
      # Immutable: each verb returns a new chain, so reuse never leaks ops.
      def js
        Phlex::Reactive::JS.new
      end

      # Root-element attributes: marks the element reactive and carries the
      # signed identity token. Spread onto the root:
      #   div(id:, **reactive_attrs) { ... }
      def reactive_attrs
        {
          data: {
            controller: "reactive",
            reactive_token_value: reactive_token
          }
        }
      end

      # The WHOLE reactive root in one spread (issue #48). reactive_attrs alone
      # doesn't emit `id:`, so `id:` and `data-controller="reactive"` can land on
      # DIFFERENT elements — putting `id:` on a child leaves the controller root's
      # `id` empty, which silently breaks token threading (the client self-matches
      # its next token by `this.element.id`) and 403s on the next action.
      #
      # reactive_root binds the id to the SAME element as reactive_attrs, so the
      # footgun is unbuildable:
      #   div(**reactive_root) { ... }                       # id + controller + token
      #   div(**reactive_root(class: "card")) { ... }        # add your own attrs
      #
      # mix deep-merges, so overrides add `class:`/`data:` without clobbering the
      # controller/token data: (a bare data: would). The id is resolved separately
      # (an explicit override wins as a clean replace, not a `mix` string-concat —
      # mix would join two String ids into "default override").
      def reactive_root(**overrides)
        root_id = overrides.delete(:id) || id
        mix({ **reactive_attrs }, overrides, { id: root_id })
      end

      # Attributes for an element that triggers an action.
      #   button(**on(:toggle)) { "○" }
      #   form(**on(:save, event: "submit")) { ... }
      #   input(**on(:update, event: "input", debounce: 300))  # live-as-you-type
      #
      # Extra keyword args become explicit params merged over collected form
      # fields. For click triggers we force type="button" so a bare button
      # inside a <form> can't submit it and cause a full-page navigation.
      #
      # `debounce:` (milliseconds) coalesces rapid events (e.g. keystrokes on an
      # "input" trigger) into ONE round trip fired after the quiet period — so
      # live-update-as-you-type doesn't POST per keystroke. A blur flushes a
      # pending dispatch so the last edit is never dropped. Omit it for the
      # immediate-dispatch default.
      #
      # `confirm:` (a message string) gates the action behind a confirmation
      # prompt (issue #52). Destructive reactive triggers can't use Hotwire's
      # `data-turbo-confirm` — the reactive controller calls preventDefault and
      # enqueues the POST itself, so Turbo's confirm handling never runs. The
      # client shows window.confirm(message) FIRST and bails before any
      # enqueue/debounce if the user declines (and prevents the native default so
      # a `submit` trigger can't navigate on cancel). Omit it for no prompt.
      #   button(**on(:destroy, confirm: "Really delete this item?")) { "Delete" }
      #
      # `event:` is interpolated verbatim into the Stimulus action descriptor
      # (`#{event}->reactive#dispatch`), so any Stimulus event string works —
      # including its native KEYBOARD FILTERS. Pass `event: "keydown.enter"` for
      # Enter-to-submit or `event: "keydown.esc"` for Escape-to-cancel, and the
      # action fires only on that key — no separate option, no client code, and
      # `key` stays free as an ordinary action-param name (on(:switch, key: …)):
      #   input(**on(:add, event: "keydown.enter"))      # Enter submits
      #   button(**on(:cancel, event: "keydown.esc"))     # Escape cancels
      #
      # `listnav:` (a CSS selector for the option elements) adds keyboard list
      # navigation to a search/combobox trigger (issue #72). It appends Stimulus
      # keyboard filters to the SAME element's data-action so Arrow Up/Down move a
      # client-side highlight among the options, Enter picks the highlighted one
      # (clicking its own reactive trigger — so selection stays a signed action),
      # and Escape clears — all with NO server round trip for the highlight (the
      # controller's listnav* handlers, like #recompute). Omit it for no nav.
      #   input(**on(:search, event: "input", debounce: 300, listnav: "[role=option]"))
      # The verbatim JSON for an empty explicit-params payload. The common
      # trigger (on(:increment), no params) hits this on EVERY render — skipping
      # params.to_json (which re-serializes {} to the same "{}" each time) avoids
      # a per-render allocation while keeping the wire format byte-identical.
      EMPTY_PARAMS_JSON = "{}"

      # The keyboard filters appended to a listnav trigger's data-action. Each is
      # a client-only handler (no POST) except Enter, which clicks the highlighted
      # option's own reactive trigger. Stimulus binds these natively.
      LISTNAV_ACTIONS = [
        "keydown.down->reactive#listnavNext",
        "keydown.up->reactive#listnavPrev",
        "keydown.enter->reactive#listnavPick",
        "keydown.esc->reactive#listnavClose"
      ].freeze

      # Event modifiers (issue #80) — window:, once:, outside:, throttle: are
      # RESERVED keyword names on on() (no longer usable as free action params):
      #
      # `window: true` binds the trigger to the window (Stimulus's native
      # `@window` descriptor suffix) — for page-level events like scroll/resize.
      # `once: true` appends Stimulus's `:once` option, so the trigger fires at
      # most one round trip and then unbinds. Both are pure descriptor
      # composition. A window-bound trigger is NOT preventDefault-ed by the
      # client (it would kill every native click/submit on the page), and it
      # skips the forced type="button" (it isn't an in-form button trigger).
      #
      # `outside: true` fires the action only for events OUTSIDE this
      # component's ROOT (containment against the reactive root element) — the
      # close-a-dropdown-on-outside-click pattern. It implies `window: true`;
      # an event inside the root is a complete client-side no-op:
      #   div(**mix(reactive_root, on(:close_menu, outside: true))) { ... }
      #
      # `throttle:` (milliseconds) rate-limits a hot trigger LEADING-EDGE: the
      # first event fires immediately, further events are suppressed until the
      # window elapses (scroll/mousemove). Mutually exclusive with `debounce:`
      # (trailing-edge) — passing both raises ArgumentError.
      #   div(**mix(reactive_root, on(:track, event: "scroll", window: true, throttle: 250)))
      #
      # `optimistic:` (issue #98) — a small, ALWAYS-REVERSIBLE vocabulary of
      # COSMETIC hints the client applies the instant the trigger fires and
      # REVERTS if the round trip fails, so a click/toggle gives instant feedback
      # instead of waiting a full round trip. Hints are visual only — never data,
      # never computed values (that would be client state). Supported ops in the
      # hint hash:
      #   * toggle_class:/add_class:/remove_class: — a class string or array,
      #     applied to the TRIGGER (default) or to a `to:` selector scoped to the
      #     root (`to: :root` targets the root element itself).
      #   * checked: :keep — for a click-bound checkbox/radio, the client SKIPS
      #     its unconditional preventDefault so the native flip happens now
      #     (today the morph never even lets it flip). On failure, the flip is
      #     reverted.
      #   * hide: true — hides the target immediately (the `hide: true` + a
      #     `reply.remove` action is the instant delete-a-row recipe: the hint
      #     hides it, the reply removes it; a failure snaps it back).
      # Success does NO cleanup: a reply that re-renders the root overwrites the
      # hint with server truth; a reply that does NOT re-render the root
      # (reply.remove / streams-only) LEAVES the hint standing — that's the
      # instant-delete working as intended.
      #   input(type: "checkbox", checked: @todo.done,
      #     **mix(on(:toggle, event: "change", optimistic: { checked: :keep }), name: "done"))
      #   button(**on(:destroy, confirm: "Delete?", optimistic: { hide: true, to: :root })) { "Delete" }
      def on(action_name, event: "click", debounce: nil, throttle: nil, confirm: nil, listnav: nil,
             window: false, once: false, outside: false, optimistic: nil, **params)
        if debounce && throttle
          raise ArgumentError,
            "on(#{action_name.inspect}) got both debounce: and throttle: — they are mutually " \
            "exclusive (debounce is trailing-edge, throttle is leading-edge); pick one"
        end

        window_bound = window || outside
        action = "#{event}#{"@window" if window_bound}->reactive#dispatch#{":once" if once}"
        action = "#{action} #{LISTNAV_ACTIONS.join(" ")}" if listnav
        attrs = {
          data: {
            action:,
            reactive_action_param: action_name.to_s,
            reactive_params_param: params.empty? ? EMPTY_PARAMS_JSON : params.to_json
          }
        }
        attrs[:data][:reactive_debounce_param] = debounce if debounce
        attrs[:data][:reactive_throttle_param] = throttle if throttle
        attrs[:data][:reactive_confirm_param] = confirm if confirm
        attrs[:data][:reactive_listnav_option_param] = listnav if listnav
        attrs[:data][:reactive_optimistic_param] = optimistic_hint_json(optimistic, action_name) if optimistic
        # STRING "true", not boolean: Phlex renders a `true` attribute VALUELESS
        # (data-reactive-outside-param), which Stimulus's param reader sees as ""
        # — falsy in JS, so the guard silently never fires. The explicit ="true"
        # typecasts to a real boolean on the client.
        attrs[:data][:reactive_outside_param] = "true" if outside
        # The client decides preventDefault behavior from event.params (never by
        # sniffing the descriptor), so EVERY window binding flags the param.
        attrs[:data][:reactive_window_param] = "true" if window_bound
        attrs[:type] = "button" if event == "click" && !window_bound
        attrs
      end

      # Attributes for a CLIENT-ONLY trigger (issue #95): binds a DOM event to a
      # chain of declarative DOM ops (Phlex::Reactive::JS) that the generic
      # controller's runOps action applies in the browser — NO token, NO params,
      # NO POST, ever. The zero-round-trip sibling of on():
      #
      #   button(**on_client(:click, js.toggle("#menu"))) { "Menu" }
      #   # tabs, one line per tab, no Stimulus controller:
      #   button(**on_client(:click, js.hide(".panel").show("#panel-2")))
      #
      # `window:`, `once:`, and `outside:` compose exactly like on()'s event
      # modifiers (#80): outside-click-to-close a dropdown is
      #   div(**mix(reactive_root, on_client(:click, js.hide("#menu"), outside: true)))
      # Window-bound triggers are never preventDefault-ed by the client and skip
      # the forced type="button".
      #
      # Ops are EPHEMERAL UI: any server re-render of the component (an action
      # reply, a broadcast, a morph) rebuilds from server state and resets
      # whatever they toggled — by design (the LiveView JS-commands caveat). Use
      # a signed action for state that must survive re-renders.
      #
      # Validation is loud: only a non-empty Phlex::Reactive::JS chain is
      # accepted — a dead trigger should fail at render, not no-op in the
      # browser.
      def on_client(event, ops, window: false, once: false, outside: false)
        unless ops.is_a?(Phlex::Reactive::JS)
          raise ArgumentError,
            "on_client expects a Phlex::Reactive::JS chain (e.g. js.toggle(\"#menu\")), " \
            "got #{ops.class}"
        end
        raise ArgumentError, "on_client(#{event.inspect}) got no ops — a dead trigger" if ops.empty?

        event = event.to_s
        window_bound = window || outside
        attrs = {
          data: {
            action: "#{event}#{"@window" if window_bound}->reactive#runOps#{":once" if once}",
            reactive_ops_param: ops.to_json
          }
        }
        # STRING "true", not boolean — same Phlex valueless-attribute trap as
        # on()'s flags above.
        attrs[:data][:reactive_outside_param] = "true" if outside
        attrs[:data][:reactive_window_param] = "true" if window_bound
        attrs[:type] = "button" if event == "click" && !window_bound
        attrs
      end

      # Bind a form control's `name` to an action param so its value travels with
      # the action — instead of hand-writing the magic `name: "value"` on every
      # input and silently getting no params when you forget it (issue #23).
      # Returns a Phlex attributes hash to spread onto any control:
      #   input(**reactive_field(:value, value: @record.name))
      #   select(**reactive_field(:status)) { ... }
      # Extra attrs merge over the binding; an explicit name: still wins (escape
      # hatch). The trigger (on(:save)) stays on the button, not the field — so
      # focusing the input doesn't dispatch and collapse edit mode.
      def reactive_field(param, **attrs)
        { name: param.to_s, **attrs }
      end

      # Render an <input> already bound to an action param (issue #23). Sugar for
      # input(**reactive_field(param, **attrs)); the value/type/etc. pass through.
      #   reactive_input(:value, value: @record.name, type: "text")
      def reactive_input(param, **attrs)
        input(**reactive_field(param, **attrs))
      end

      # Data attributes declaring a client-side compute for the root element.
      # Spread ALONGSIDE reactive_root so the generic controller can find the
      # reducer and the named input/output fields inside this root:
      #   div(**mix(reactive_root, reactive_compute_attrs(:payment_split))) { … }
      #
      # It emits the reducer key plus the input/output field names as JSON so the
      # client runs the reducer on `input`, writes the outputs with no round trip,
      # then the debounced POST reconciles from the server reply. Raises for an
      # undeclared compute — a silent no-op would leave the field wiring dead.
      def reactive_compute_attrs(name)
        definition = self.class.reactive_compute(name)
        raise Error, "#{self.class} has no reactive_compute #{name.inspect}" unless definition

        {
          data: {
            reactive_compute_reducer_param: definition.reducer,
            reactive_compute_inputs_param: definition.inputs.map(&:to_s).to_json,
            reactive_compute_outputs_param: definition.outputs.map(&:to_s).to_json
          }
        }
      end

      # Render a <select> bound to an action param (issue #23). The options block
      # is the element's content, so the awkward FormBuilder positional split
      # (where name: lands after the options/html-options args) goes away:
      #   reactive_select(:status) { @statuses.each { |s| option(value: s, selected: s == @record.status) { s } } }
      def reactive_select(param, **attrs, &)
        select(**reactive_field(param, **attrs), &)
      end

      # Map a declared nested param onto Rails' <assoc>_attributes, carrying the
      # existing associated record's id so accepts_nested_attributes_for matches
      # it IN PLACE instead of building a second one (issue #24). Returns the
      # update hash; pass it to update!:
      #   def save(address:) = nested_update!(:address, address)
      # The id is only added when the association already exists, so the first
      # save (no associated record yet) creates one cleanly. The given attrs are
      # not mutated.
      def nested_attributes(association, attrs)
        merged = attrs.dup
        existing = reactive_record_for_nested.public_send(association)
        merged[:id] = existing.id if existing

        { "#{association}_attributes": merged }
      end

      # Map a nested param onto <assoc>_attributes (with id preservation) AND
      # apply it to the component's record in one call (issue #24). Extra keyword
      # attributes update alongside the association.
      #   def save(address:, name:) = nested_update!(:address, address, name:)
      def nested_update!(association, attrs, **extra)
        reactive_record_for_nested.update!(**nested_attributes(association, attrs), **extra)
      end

      # The declared optimistic-hint class ops (issue #98): the cosmetic class
      # vocabulary the client applies instantly and reverts on failure. Enforced
      # at build time in optimistic_hint_json (default-deny — a dead hint fails
      # at render, not silently in the browser). Each carries a class string or
      # array; hide/checked are flags with a fixed shape.
      OPTIMISTIC_CLASS_OPS = %w[toggle_class add_class remove_class].freeze

      private

      # Normalize + validate the optimistic hint hash, returning its JSON wire
      # form (data-reactive-optimistic-param). `to: :root` becomes the same
      # "@root" sentinel the js op builder uses so the client resolves it
      # uniformly. Unknown keys, a bad `checked:` value, or a non-hash raise —
      # a hint that can't apply must fail loudly at render.
      def optimistic_hint_json(optimistic, action_name)
        unless optimistic.is_a?(Hash)
          raise ArgumentError,
            "on(#{action_name.inspect}) optimistic: must be a Hash of visual hints " \
            "(e.g. { checked: :keep } or { hide: true, to: :root }), got #{optimistic.class}"
        end

        hint = {}
        optimistic.each do |key, value|
          case key.to_s
          when *OPTIMISTIC_CLASS_OPS
            hint[key.to_s] = Array(value).map(&:to_s)
          when "hide"
            hint["hide"] = value ? true : false
          when "checked"
            unless value.to_s == "keep"
              raise ArgumentError,
                "on(#{action_name.inspect}) optimistic checked: only supports :keep " \
                "(flip the native control, revert on failure), got #{value.inspect}"
            end
            hint["checked"] = "keep"
          when "to"
            hint["to"] = value == :root ? Phlex::Reactive::JS::ROOT_SENTINEL : value.to_s
          else
            raise ArgumentError,
              "on(#{action_name.inspect}) got an unknown optimistic hint #{key.inspect} — " \
              "supported: toggle_class/add_class/remove_class, checked: :keep, hide: true, to:"
          end
        end

        hint.to_json
      end

      # The component's record, for the nested-attributes helpers. Requires a
      # declared reactive_record (the nested helper only makes sense for a
      # record-backed component).
      def reactive_record_for_nested
        key = self.class.reactive_record_key
        raise Error, "#{self.class} must declare `reactive_record` to use nested_update!/nested_attributes" unless key

        instance_variable_get(:"@#{key}")
      end

      # Signed identity payload: the class name plus whichever identity pieces
      # the component declares — a record GlobalID (`gid`), signed state (`s`),
      # or both. Keeping them in ONE MessageVerifier payload makes the state
      # (e.g. which column an inline_edit may write) tamper-proof alongside the
      # record. Record-only ({c, gid}) and state-only ({c, s}) shapes are
      # unchanged.
      #
      # A record that is NOT YET PERSISTED (new_record?) has no id → no GlobalID
      # (to_gid raises MissingModelIdError). A record-backed component may render
      # such a draft (an unsaved order the user is building): we OMIT gid and rely
      # on the declared state (reactive_state) as the draft seed, so the token
      # still signs cleanly and the client controller mounts. The draft is then
      # driven client-side (reactive_compute) until it's saved; once persisted, a
      # re-render signs the gid as usual. If the record is unsaved AND no state is
      # declared, the token carries just {c} — enough to mount, but with no
      # identity to round-trip, so declare reactive_state for a draft you sync.
      def reactive_token
        klass = self.class
        payload = { "c" => klass.name }

        if (record_ivar = klass.reactive_record_ivar)
          record = instance_variable_get(record_ivar)
          payload["gid"] = record.to_gid.to_s unless record.respond_to?(:persisted?) && !record.persisted?
        end

        state_ivars = klass.reactive_state_ivars
        unless state_ivars.empty?
          state = {}
          state_ivars.each { |key, ivar| state[key] = instance_variable_get(ivar).as_json }
          payload["s"] = state
        end

        Phlex::Reactive.sign(payload)
      end
    end
  end
end
