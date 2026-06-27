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

      class_methods do
        # Declare the ActiveRecord (GlobalID-able) record this component is
        # rebuilt from. The signed token carries its GlobalID; the server
        # re-finds it on each action. State lives in the DB.
        def reactive_record(name)
          @reactive_record_key = name.to_sym
        end

        def reactive_record_key
          return @reactive_record_key if defined?(@reactive_record_key)

          superclass.respond_to?(:reactive_record_key) ? superclass.reactive_record_key : nil
        end

        # Opt into signed STATE for record-less components only.
        #   reactive_state :count, :open
        def reactive_state(*names)
          reactive_state_keys.concat(names.map(&:to_sym))
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
            reactive_state_keys.each do |key|
              # Use key presence, not the value: a signed `nil` (nullable state)
              # must round-trip distinctly. Only a genuinely absent key falls
              # back to the component's initialize default; `false` and `nil`
              # both survive.
              next unless state.key?(key.to_s)

              kwargs[key] = state[key.to_s]
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
      def on(action_name, event: "click", debounce: nil, **params)
        attrs = {
          data: {
            action: "#{event}->reactive#dispatch",
            reactive_action_param: action_name.to_s,
            reactive_params_param: params.to_json
          }
        }
        attrs[:data][:reactive_debounce_param] = debounce if debounce
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
        {name: param.to_s, **attrs}
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
      def reactive_select(param, **attrs, &block)
        select(**reactive_field(param, **attrs), &block)
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

        {"#{association}_attributes": merged}
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
        unless key
          raise Error, "#{self.class} must declare `reactive_record` to use nested_update!/nested_attributes"
        end

        instance_variable_get(:"@#{key}")
      end

      # Signed identity payload: the class name plus whichever identity pieces
      # the component declares — a record GlobalID (`gid`), signed state (`s`),
      # or both. Keeping them in ONE MessageVerifier payload makes the state
      # (e.g. which column an inline_edit may write) tamper-proof alongside the
      # record. Record-only ({c, gid}) and state-only ({c, s}) shapes are
      # unchanged.
      def reactive_token
        payload = {"c" => self.class.name}

        if self.class.reactive_record_key
          record = instance_variable_get(:"@#{self.class.reactive_record_key}")
          payload["gid"] = record.to_gid.to_s
        end

        if self.class.reactive_state_keys.any?
          payload["s"] = self.class.reactive_state_keys.to_h do |k|
            [k.to_s, instance_variable_get(:"@#{k}").as_json]
          end
        end

        Phlex::Reactive.sign(payload)
      end
    end
  end
end
