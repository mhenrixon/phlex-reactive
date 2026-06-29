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
    # Include alongside Phlex::Reactive::Streamable (which provides #id and the
    # re-render machinery).
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
    # Usage (record-backed):
    #   class Todos::Item < ApplicationComponent
    #     include Phlex::Reactive::Streamable
    #     include Phlex::Reactive::Component
    #
    #     reactive_record :todo
    #     action :toggle
    #     action :rename, params: { title: :string }
    #
    #     def initialize(todo:) = @todo = todo
    #     def id = dom_id(@todo)
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

      # A declared, client-invokable action and its param schema.
      Action = Data.define(:name, :params)

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
      # The verbatim JSON for an empty explicit-params payload. The common
      # trigger (on(:increment), no params) hits this on EVERY render — skipping
      # params.to_json (which re-serializes {} to the same "{}" each time) avoids
      # a per-render allocation while keeping the wire format byte-identical.
      EMPTY_PARAMS_JSON = "{}"

      def on(action_name, event: "click", debounce: nil, confirm: nil, **params)
        attrs = {
          data: {
            action: "#{event}->reactive#dispatch",
            reactive_action_param: action_name.to_s,
            reactive_params_param: params.empty? ? EMPTY_PARAMS_JSON : params.to_json
          }
        }
        attrs[:data][:reactive_debounce_param] = debounce if debounce
        attrs[:data][:reactive_confirm_param] = confirm if confirm
        attrs[:type] = "button" if event == "click"
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

      private

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
      def reactive_token
        klass = self.class
        payload = { "c" => klass.name }

        if (record_ivar = klass.reactive_record_ivar)
          payload["gid"] = instance_variable_get(record_ivar).to_gid.to_s
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
