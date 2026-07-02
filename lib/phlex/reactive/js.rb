# frozen_string_literal: true

module Phlex
  module Reactive
    # An immutable, chainable builder of client-side DOM commands (issue #95) —
    # the ops behind Component#on_client. Each verb returns a NEW frozen
    # instance; #to_json emits the wire format the generic controller's runOps
    # action interprets, entirely in the browser:
    #
    #   button(**on_client(:click, js.toggle("#menu"))) { "Menu" }
    #   # -> data-reactive-ops-param='[["toggle",{"to":"#menu"}]]'
    #
    # These are declarative DOM OPERATIONS, not state: nothing is shipped back
    # to the server, nothing is trusted from the client, and any server
    # re-render of the component resets whatever they toggled (the LiveView
    # JS-commands caveat — by design; use a signed action for state that must
    # survive re-renders).
    #
    # Targets: a CSS selector string is resolved WITHIN the component's root by
    # default (nested reactive roots excluded, issue #15 semantics); `:root`
    # targets the root element itself; `global: true` opts a single op out of
    # root scoping (document escape hatch, e.g. a page-level overlay).
    #
    # The op vocabulary is a fixed whitelist mirrored by the client interpreter
    # — an op name the client doesn't know is warn-and-skipped there
    # (client-side default-deny). Validation here is deliberately LOUD: a bad
    # target or an empty class list raises at render time rather than silently
    # doing nothing in the browser.
    class JS
      # Serialized stand-in for "the component's own root element".
      ROOT_SENTINEL = "@root"

      # The accumulated [name, args] op pairs, oldest first. Frozen.
      attr_reader :ops

      def initialize(ops = [].freeze)
        @ops = ops
        freeze
      end

      # --- Visibility (the `hidden` attribute) ---

      def show(to, global: false)
        append("show", target_args(to, global:))
      end

      def hide(to, global: false)
        append("hide", target_args(to, global:))
      end

      def toggle(to, global: false)
        append("toggle", target_args(to, global:))
      end

      # --- Classes ---

      def add_class(to, *classes, global: false)
        append("add_class", class_args(to, classes, global:))
      end

      def remove_class(to, *classes, global: false)
        append("remove_class", class_args(to, classes, global:))
      end

      def toggle_class(to, *classes, global: false)
        append("toggle_class", class_args(to, classes, global:))
      end

      # The wire format: a JSON array of [op, args] pairs, applied in order.
      def to_json(*)
        @ops.to_json
      end

      def empty?
        @ops.empty?
      end

      private

      # Immutability: every verb funnels here and returns a NEW frozen chain —
      # a builder held in a constant or memo can never be mutated by later use.
      def append(name, args)
        self.class.new([*@ops, [name, args].freeze].freeze)
      end

      def target_args(to, global:)
        args = { "to" => normalize_target(to) }
        args["global"] = true if global
        args.freeze
      end

      def class_args(to, classes, global:)
        if classes.empty?
          raise ArgumentError, "#{self.class}: a class op needs at least one class (got none for #{to.inspect})"
        end

        args = { "to" => normalize_target(to), "classes" => classes.map(&:to_s).freeze }
        args["global"] = true if global
        args.freeze
      end

      # :root -> the sentinel; a String passes through as a CSS selector.
      # Anything else (a stray symbol, nil) is a bug at the call site — raise at
      # render time instead of silently matching nothing in the browser.
      def normalize_target(to)
        return ROOT_SENTINEL if to == :root
        return to if to.is_a?(String)

        raise ArgumentError,
          "#{self.class}: target must be :root or a CSS selector string, got #{to.inspect}"
      end
    end
  end
end
