# frozen_string_literal: true

module Phlex
  module Reactive
    # The effects vocabulary (issue #215): animate a component's ENTER
    # (append/prepend), EXIT (remove), and UPDATE (replace/update, plain or
    # morph) when a Turbo Stream renders. Strictly OPT-IN at three levels,
    # most specific wins:
    #
    #   Phlex::Reactive.effects = true                    # global default set
    #   reactive_effects enter: :slide, update: false     # per component
    #   reply.remove(effect: :shake)                      # per call
    #
    # An effect value is a BUILT-IN name (:fade/:slide/:scale/:highlight/
    # :shake — shipped as CSS in app/assets/stylesheets/phlex/reactive/
    # effects.css), :random (the client picks a built-in per application),
    # false (disable the hook), or custom NAMED LEGS { during:, from:, to: }
    # — the issue #186 class-list vocabulary, compiled to the same
    # [during, from, to] wire array the client's runTransition consumes.
    #
    # This module owns normalization (declare-time validation — a typo'd
    # effect raises at class load / config time, not at click time) and the
    # WIRE forms:
    #   * root attrs:  data-reactive-effect-enter="fade" (emitted by
    #     reactive_attrs; resolved global ⊕ component)
    #   * per call:    data-reactive-effect="shake" on the <turbo-stream>
    #     element itself ("off" suppresses; beats the root attrs)
    # Values are either a name or the legs JSON array — the client
    # distinguishes by the leading "[".
    module Effects
      HOOKS = %i[enter exit update].freeze
      BUILT_INS = %w[fade slide scale highlight shake].freeze
      RANDOM = "random"
      OFF = "off"
      LEG_KEYS = %i[during from to].freeze

      # The `effects = true` sugar — pre-normalized wire strings.
      DEFAULTS = { enter: "fade", exit: "fade", update: "highlight" }.freeze

      class << self
        # Normalize the Phlex::Reactive.effects= value: nil/false → off (nil),
        # true → the default set, a Hash → validated per-hook wire strings.
        def normalize_config(value)
          case value
          when nil, false then nil
          when true then DEFAULTS
          when Hash then normalize!(value)
          else
            raise ArgumentError,
              "Phlex::Reactive.effects takes nil/false (off), true (the default set), or a " \
              "{ enter:/exit:/update: } hash — got #{value.inspect}"
          end
        end

        # Validate + compile a per-hook declaration hash to its stored form:
        # { hook => wire-string | false }. `false` survives normalization so a
        # component-level `update: false` can OVERRIDE a global update effect
        # at resolve time (the merge keeps it; attr emission skips it).
        def normalize!(hooks)
          hooks.each_with_object({}) do |(hook, value), out|
            key = hook.to_sym
            unless HOOKS.include?(key)
              raise ArgumentError,
                "unknown effects hook #{hook.inspect} — valid hooks: #{HOOKS.join(", ")}"
            end
            out[key] = value == false ? false : wire_value(value)
          end.freeze
        end

        # The RESOLVED root attrs for a component class: global ⊕ component
        # (Hash#merge — the component's per-hook values win), false hooks
        # dropped at emission (they exist to cancel a global hook), the whole
        # thing nil when everything is off. `reactive_effects false` opts the
        # class out regardless of the global set. Returns a frozen
        # { reactive_effect_<hook>: wire } fragment ready for data.merge!.
        def root_attrs_for(klass)
          component = klass.respond_to?(:reactive_effects_config) ? klass.reactive_effects_config : nil
          return nil if component == false

          global = Phlex::Reactive.effects
          resolved =
            if global && component then global.merge(component)
            else global || component
            end
          return nil if resolved.nil? || resolved.empty?

          attrs = {}
          resolved.each do |hook, wire|
            attrs[:"reactive_effect_#{hook}"] = wire unless wire == false
          end
          attrs.empty? ? nil : attrs.freeze
        end

        # Stamp a built turbo-stream tag with the PER-CALL effect override:
        # `data-reactive-effect` on the <turbo-stream> element itself (it beats
        # the root-declared attrs on the client; "off" suppresses them). String
        # injection into the opening tag — turbo-rails' TagBuilder only takes
        # `method:` as a tag attribute, and hand-built escaped attrs are the
        # to_stream_token precedent. `.sub` hits the FIRST "<turbo-stream",
        # which is always the opening tag (template content is escaped or
        # nested later). nil = not given → the input passes through UNTOUCHED
        # (byte-identical wire). Value validated + escaped — a legs JSON's
        # quotes land as &quot;.
        def annotate(html, effect)
          return html if effect.nil?

          attr = %( data-reactive-effect="#{ERB::Util.html_escape(wire_value(effect))}")
          html.to_s.sub("<turbo-stream", "<turbo-stream#{attr}").html_safe
        end

        # ONE effect value → its wire string: a built-in/random name, "off"
        # (per-call suppression), or the legs JSON array.
        def wire_value(value)
          case value
          when false then OFF
          when Symbol, String then named_wire(value.to_s)
          when Hash then legs_wire(value)
          when Array then raise_positional_legs(value)
          else
            raise ArgumentError,
              "effect must be a built-in (#{BUILT_INS.join(", ")}), :random, false, or " \
              "{ during:, from:, to: } legs — got #{value.inspect}"
          end
        end

        private

        def named_wire(name)
          return name if name == RANDOM || BUILT_INS.include?(name)

          raise ArgumentError,
            "unknown effect #{name.inspect} — built-ins: #{BUILT_INS.join(", ")}, :random, " \
            "or { during:, from:, to: } legs"
        end

        # Named legs (issue #186 vocabulary) → the [during, from, to] wire
        # array runTransition consumes. Class lists may be a String or an
        # Array of strings.
        def legs_wire(legs)
          unless LEG_KEYS.all? { legs.key?(it) }
            raise ArgumentError,
              "effect legs must name during:, from:, to: class lists — got #{legs.inspect}"
          end

          JSON.generate(LEG_KEYS.map { Array(legs[it]).join(" ") })
        end

        # The old positional triple — reject with the named-legs rewrite, the
        # same guidance js.rb's normalize_transition gives (issue #186).
        def raise_positional_legs(value)
          d, f, t = value
          raise ArgumentError,
            "effect legs take named keys (issue #186 vocabulary) — " \
            "{ during: #{d.inspect}, from: #{f.inspect}, to: #{t.inspect} }"
        end
      end
    end
  end
end
