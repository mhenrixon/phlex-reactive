# frozen_string_literal: true

module Phlex
  module Reactive
    # Component turns a self-contained Phlex component into a Livewire-style
    # reactive unit: declare actions in Ruby, and the generic `reactive`
    # Stimulus controller wires clicks/inputs to an HTTP round trip that
    # re-renders the component and morphs it back into the DOM. No per-feature
    # Stimulus controllers, no hand-picked Turbo targets.
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
    #     signs the listed instance variables. Use only when there is genuinely
    #     no record to re-find.
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
        # Param types: :string (default), :integer, :float, :boolean.
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
        def from_identity(payload)
          if reactive_record_key
            record = GlobalID::Locator.locate(payload.fetch("gid"))
            raise(ActiveRecord::RecordNotFound, "reactive record missing") unless record

            new(reactive_record_key => record)
          else
            state = payload.fetch("s", {})
            kwargs = reactive_state_keys.to_h { |k| [k, state[k.to_s]] }.compact
            new(**kwargs)
          end
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
      #
      # Extra keyword args become explicit params merged over collected form
      # fields. For click triggers we force type="button" so a bare button
      # inside a <form> can't submit it and cause a full-page navigation.
      def on(action_name, event: "click", **params)
        attrs = {
          data: {
            action: "#{event}->reactive#dispatch",
            reactive_action_param: action_name.to_s,
            reactive_params_param: params.to_json
          }
        }
        attrs[:type] = "button" if event == "click"
        attrs
      end

      private

      # Signed { c, gid } (record-backed) or { c, s } (state-backed).
      def reactive_token
        payload =
          if self.class.reactive_record_key
            record = instance_variable_get(:"@#{self.class.reactive_record_key}")
            {"c" => self.class.name, "gid" => record.to_gid.to_s}
          else
            state = self.class.reactive_state_keys.to_h do |k|
              [k.to_s, instance_variable_get(:"@#{k}").as_json]
            end
            {"c" => self.class.name, "s" => state}
          end

        Phlex::Reactive.sign(payload)
      end
    end
  end
end
