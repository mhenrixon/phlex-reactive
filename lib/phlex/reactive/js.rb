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

      # The attribute-name allowlist (issue #96) — the security-critical part of
      # the attr ops, enforced HERE at build time AND again in the client
      # interpreter (two-sided default-deny: a hand-built ops attr must not
      # bypass it either). Rejected:
      #   * /\Aon/i        — event-handler attributes (onclick, onmouseover) → XSS.
      #   * the URL set     — href/src/srcdoc/action/formaction/xlink:href can carry
      #                       a `javascript:` payload; setting them from client ops
      #                       is a navigation/injection surface, not a UI toggle.
      #   * style           — inline CSS injection; use classes (add_class/...).
      # The INTENDED surface is class ops plus boolean/state attributes:
      #   hidden, disabled, open, selected, aria-*, data-*.
      URL_BEARING_ATTRS = %w[href src srcdoc action formaction xlink:href].freeze
      EVENT_HANDLER_ATTR = /\Aon/i

      # The attr ops whose args carry a "name" the allowlist must gate. Used to
      # re-validate a RAW [op, args] list (the js([...]) / broadcast_js_to([...])
      # escape hatch) that skips the builder's build-time attr_args check.
      ATTR_NAME_OPS = %w[set_attr remove_attr toggle_attr].freeze

      # Validate a raw ops list ([[op, args], ...] as passed to js/broadcast_js_to
      # without the builder) against the attribute allowlist, so the escape hatch
      # gets the SAME server-side default-deny as the JS chain (defense in depth;
      # the client also enforces it). Non-attr ops and malformed entries pass
      # through untouched — the client interpreter default-denies unknown ops.
      # :root -> the sentinel; a String passes through as a CSS selector. Shared
      # by the js op builder AND the on() pending-state hint normalizer (issue
      # #181) so BOTH resolve a `to:` target through one code path. Anything else
      # (a stray symbol, nil) is a bug at the call site — raise at render time
      # instead of silently matching nothing in the browser.
      def self.normalize_target(to)
        return ROOT_SENTINEL if to == :root
        return to if to.is_a?(String)

        raise ArgumentError,
          "target must be :root or a CSS selector string, got #{to.inspect}"
      end

      def self.assert_ops_allowed!(list)
        Array(list).each do |op, args|
          next unless ATTR_NAME_OPS.include?(op.to_s) && args.is_a?(::Hash)

          name = args["name"] || args[:name]
          assert_allowed_attr(name.to_s) if name
        end
      end

      # The attribute-name allowlist (issue #96), case-insensitive. Refuses
      # event-handler (on*), URL-bearing, and style attributes. Enforced at build
      # time by the instance builder AND on the raw-list escape hatch — two-sided
      # default-deny with the client interpreter.
      def self.assert_allowed_attr(name)
        lower = name.downcase
        if name.match?(EVENT_HANDLER_ATTR)
          raise ArgumentError,
            "#{self}: attribute #{name.inspect} is an event handler (on*) — refused (XSS). " \
            "Client attr ops target hidden/disabled/open/selected/aria-*/data-* and classes."
        end
        return unless URL_BEARING_ATTRS.include?(lower) || lower == "style"

        raise ArgumentError,
          "#{self}: attribute #{name.inspect} is refused — URL-bearing attributes " \
          "(#{URL_BEARING_ATTRS.join(", ")}) and `style` can't be set from client ops " \
          "(injection surface). Use classes for styling; target aria-*/data-*/boolean attrs."
      end

      # The accumulated [name, args] op pairs, oldest first. Frozen.
      attr_reader :ops

      def initialize(ops = [].freeze)
        @ops = ops
        freeze
      end

      # --- Visibility (the `hidden` attribute) ---
      #
      # `transition:` (issue #96) — an optional [during, from, to] class triple
      # animated around the visibility flip: `during`+`from` are applied, then on
      # the next frame `from`→`to` swaps, and the whole set is awaited via
      # `animationend` (with a setTimeout fallback so a non-animated element never
      # hangs the op chain). Omit it for the instant flip.

      def show(to, global: false, transition: nil)
        append("show", target_args(to, global:, transition:))
      end

      def hide(to, global: false, transition: nil)
        append("hide", target_args(to, global:, transition:))
      end

      def toggle(to, global: false, transition: nil)
        append("toggle", target_args(to, global:, transition:))
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

      # --- Attributes (issue #96) — allowlisted names only ---
      #
      # set_attr(to, name, value) / remove_attr(to, name) / toggle_attr(to, name).
      # The value is stringified (a Phlex-style flag rides as the string "true",
      # never a valueless attribute). The name is checked against the allowlist at
      # build time — an event-handler, URL-bearing, or style name raises here.

      def set_attr(to, name, value, global: false)
        append("set_attr", attr_args(to, name, global:, value:))
      end

      def remove_attr(to, name, global: false)
        append("remove_attr", attr_args(to, name, global:))
      end

      def toggle_attr(to, name, global: false)
        append("toggle_attr", attr_args(to, name, global:))
      end

      # --- Focus (issue #96) ---
      #
      # focus(to)        — focus the FIRST match of the selector.
      # focus_first(to)  — focus the first FOCUSABLE DESCENDANT of the match
      #                    (e.g. focus the first menuitem inside an opened menu).

      def focus(to, global: false)
        append("focus", target_args(to, global:))
      end

      def focus_first(to, global: false)
        append("focus_first", target_args(to, global:))
      end

      # --- Submit (issue #226) ---
      #
      # submit(to = :root) — requestSubmit() the TARGET'S OWN form: the target
      # itself when it IS a form, else its form owner (input.form, honoring a
      # form= attribute), else the nearest ancestor form. requestSubmit runs
      # constraint validation and fires a REAL cancelable `submit` event, so it
      # composes with both a native/Turbo form and an on(:action, event:
      # "submit") interception. ACTOR-ONLY like focus: allowed from on_client /
      # reply.js / a reducer's $ops, refused in broadcast_to(js:) — a broadcast
      # submit would force-submit every subscriber's form.

      def submit(to = :root, global: false)
        append("submit", target_args(to, global:))
      end

      # --- Text content (issue #159) ---
      #
      # text(to, value) — set the target's textContent (stringified; nil clears).
      # XSS-safe by construction: textContent only, NEVER innerHTML — strictly
      # less powerful than set_attr. Pair with `global: true` to paint a value
      # into a node OUTSIDE the component's root (the cross-root text escape,
      # e.g. a read-only recap in another tab pane).

      def text(to, value, global: false)
        args = { "to" => normalize_target(to), "value" => value.to_s }
        args["global"] = true if global
        append("text", args.freeze)
      end

      # --- Dispatch a bubbling CustomEvent (issue #96) ---
      #
      # dispatch(name, to: nil, detail: {}) — emit a bubbling CustomEvent so other
      # components/controllers can react to a client-only interaction without a
      # round trip. `to:` picks the element to dispatch ON (nil → the component
      # root, serialized as the @root sentinel so the client resolves it
      # uniformly); `detail:` is the event's `detail` payload. The client uses raw
      # element.dispatchEvent — the shared controller SHADOWS Stimulus's
      # this.dispatch helper, so the interpreter must not use it.
      def dispatch(name, to: nil, detail: {}, global: false)
        args = { "name" => name.to_s, "to" => normalize_target(to.nil? ? :root : to), "detail" => detail }
        args["global"] = true if global
        append("dispatch", args.freeze)
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

      def target_args(to, global:, transition: nil)
        args = { "to" => normalize_target(to) }
        args["global"] = true if global
        args["transition"] = normalize_transition(transition) if transition
        args.freeze
      end

      # An attr op's args: the target, the allowlisted name, an optional
      # (stringified) value. The name is validated LOUDLY at build time.
      def attr_args(to, name, global:, value: :__none)
        name = name.to_s
        assert_allowed_attr(name)
        args = { "to" => normalize_target(to), "name" => name }
        args["value"] = value.to_s unless value == :__none
        args["global"] = true if global
        args.freeze
      end

      # Build-time attr-name allowlist for the instance builder — delegates to the
      # shared class-method check (also used by the raw-list escape hatch).
      def assert_allowed_attr(name)
        self.class.assert_allowed_attr(name)
      end

      # A transition is NAMED legs { during:, from:, to: } (issue #186), compiled to
      # the [during, from, to] wire array (zero client change). The old positional
      # Array form is removed — it raises with the caller's OWN values slotted into
      # the named form, so the rewrite is copy-pasteable.
      def normalize_transition(transition)
        if transition.is_a?(Array)
          d, f, t = transition
          raise ArgumentError,
            "#{self.class}: transition: takes named legs (issue #186) — " \
            "transition: { during: #{d.inspect}, from: #{f.inspect}, to: #{t.inspect} }"
        end
        unless transition.is_a?(Hash) && %i[during from to].all? { transition.key?(it) }
          raise ArgumentError,
            "#{self.class}: transition: must name during:, from:, to: class lists, got #{transition.inspect}"
        end

        [transition[:during], transition[:from], transition[:to]].map(&:to_s).freeze
      end

      def class_args(to, classes, global:)
        if classes.empty?
          raise ArgumentError, "#{self.class}: a class op needs at least one class (got none for #{to.inspect})"
        end

        args = { "to" => normalize_target(to), "classes" => classes.map(&:to_s).freeze }
        args["global"] = true if global
        args.freeze
      end

      # Instance-side alias for the class method (used by the op builder). See
      # JS.normalize_target — the shared :root/selector translation.
      def normalize_target(to) = self.class.normalize_target(to)
    end
  end
end
