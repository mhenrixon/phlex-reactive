# frozen_string_literal: true

module Phlex
  module Reactive
    # Deferred reply segments (issue #165): the machinery behind reply.defer —
    # "placeholder now, the real render to the ACTOR when ready".
    #
    # A Response only RECORDS segments (see Response#defer); this module turns
    # them into wire streams at the ENDPOINT, after the action's transaction
    # committed — so a rolled-back action can never leak a directive — and picks
    # the delivery lane:
    #
    #   * pull (:fetch)  — the directive carries a purpose-scoped, short-TTL
    #     defer token; the client POSTs it to the defer endpoint OFF the action
    #     queue and applies the rendered stream when it lands. Works on every
    #     transport (it's just HTTP) — this is the universal lane.
    #   * push (:stream) — pgbus durable one-shot stream + ActiveJob: the reply
    #     carries a signed SSE src; a job renders and broadcasts durably, and
    #     the since-id=0 replay closes the broadcast-before-subscribe race.
    #     Capability-gated (Phlex::Reactive.defer_push_capable?); anything
    #     missing degrades to pull.
    module Defer
      # One recorded deferred segment. `component` is the built (but not yet
      # rendered) reactive component; `placeholder` is nil (keep current
      # content, mark pending), true (the component's deferred_placeholder /
      # the built-in shell), a String, or a Phlex component; `morph` makes the
      # ARRIVAL morph instead of replace (issue #28 semantics).
      Segment = Data.define(:component, :placeholder, :morph)

      # The custom turbo-stream action the client's defer handler registers.
      DIRECTIVE_ACTION = "reactive:defer"

      class << self
        # Which lane deferred segments take, resolved PER REPLY (capability is
        # probed live — cheap: without pgbus it's one defined? short-circuit).
        # :fetch forces pull; :stream requests push and DEGRADES to pull with a
        # one-time warning when the capability is absent (never break); :auto
        # picks push iff fully capable.
        def resolve_via
          case Phlex::Reactive.defer_transport
          when :fetch then :fetch
          when :stream
            return :stream if Phlex::Reactive.defer_push_capable?

            warn_stream_degraded
            :fetch
          else
            Phlex::Reactive.defer_push_capable? ? :stream : :fetch
          end
        end

        # The wire streams for ONE segment on the given lane, in apply order:
        # the optional placeholder shell FIRST (so the pending state paints
        # before the directive kicks off delivery), then the directive.
        def streams_for(segment, via: resolve_via)
          streams = []
          shell = placeholder_stream(segment)
          streams << shell if shell
          streams << directive_stream(segment, via)
          streams
        end

        # Validate reply.defer arguments LOUDLY at the call site — a dead
        # segment (a component the endpoint could never rebuild, a bogus
        # placeholder) must fail in the action that wrote it, not silently at
        # reply render or, worse, at fetch time.
        def validate_segment!(component, placeholder)
          unless component.class.include?(Phlex::Reactive::Component)
            raise ::ArgumentError,
              "reply.defer expects a Phlex::Reactive::Component instance (its identity is what the " \
              "deferred render is rebuilt from) — got #{component.class}"
          end

          return if placeholder.nil? || placeholder == true ||
                    placeholder.is_a?(::String) || placeholder.is_a?(::Phlex::SGML)

          raise ::ArgumentError,
            "reply.defer placeholder: must be nil (keep current content), true (the component's " \
            "deferred_placeholder or the built-in shell), a String, or a Phlex component — " \
            "got #{placeholder.class}"
        end

        private

        # The delivery directive: `<turbo-stream action="reactive:defer">`
        # targeting the deferred component's own #id. The pull form carries the
        # purpose-scoped, short-TTL defer token; morph mode rides INSIDE the
        # signed payload so the client can't flip it. Wrapped in a Stream so the
        # endpoint's token guards read it structurally (it never carries
        # data-reactive-token-value, so it can never count as a token refresh).
        def directive_stream(segment, via)
          target = segment.component.id
          html = %(<turbo-stream action="#{DIRECTIVE_ACTION}" \
target="#{ERB::Util.html_escape(target)}"#{directive_attrs(segment, via)}></turbo-stream>)
          Phlex::Reactive::Stream.wrap(
            html.html_safe, action: DIRECTIVE_ACTION, target: target, renders_root: false
          )
        end

        def directive_attrs(segment, via)
          case via
          when :stream then push_directive_attrs(segment)
          else fetch_directive_attrs(segment)
          end
        end

        def fetch_directive_attrs(segment)
          token = mint_token(segment)
          %( data-reactive-defer-via="fetch" data-reactive-defer-token="#{ERB::Util.html_escape(token)}")
        end

        # Sign the component's identity (the SAME payload shape as the action
        # token — reactive_identity_payload, so the families can't drift) under
        # the defer purpose + TTL. Private on the component; reached via send
        # exactly like the identity internals are elsewhere off-instance.
        def mint_token(segment)
          payload = segment.component.send(:reactive_identity_payload)
          payload = payload.merge("m" => "morph") if segment.morph
          Phlex::Reactive.sign_defer(payload)
        end

        # The pending shell: replaces the target with a div that OWNS the
        # component's id (so any placeholder content works — the shell is the
        # stream target) and carries the pending markers the client/CSS hook
        # onto. nil when the segment keeps current content (the client's
        # directive handler marks the live element instead). Deliberately NO
        # defer token on the shell — the directive owns delivery; a token attr
        # here would double-fetch via the lazy-mount connect probe.
        def placeholder_stream(segment)
          inner = placeholder_inner_html(segment)
          return nil if inner.nil?

          target = segment.component.id
          shell = %(<div id="#{ERB::Util.html_escape(target)}" class="reactive-defer-placeholder" \
data-reactive-defer-pending="true" aria-busy="true">#{inner}</div>)
          Phlex::Reactive::Stream.wrap(
            Phlex::Reactive.stream_builder.replace(target, html: shell.html_safe),
            action: "replace", target: target, renders_root: true
          )
        end

        # Resolve the segment's placeholder to inner HTML — nil means "no
        # shell". Same content contract as flash/also_update: a Phlex component
        # renders through the configured renderer (auto-escaped), a plain
        # String is DATA and gets escaped, an html_safe String is intentional
        # markup and passes verbatim (ERB::Util.html_escape's own contract).
        def placeholder_inner_html(segment)
          value = resolved_placeholder(segment)
          return nil if value == :none

          case value
          when ::Phlex::SGML then Phlex::Reactive.render(value)
          else ERB::Util.html_escape(value.to_s)
          end
        end

        # `true` asks the COMPONENT: deferred_placeholder (private ok) when
        # defined, else the built-in empty shell (the pending markers + the
        # .reactive-defer-placeholder class are the whole skeleton). nil from
        # the method degrades to the empty shell too — the caller explicitly
        # asked for a placeholder.
        def resolved_placeholder(segment)
          case segment.placeholder
          when nil then :none
          when true
            component = segment.component
            if component.respond_to?(:deferred_placeholder, true)
              component.send(:deferred_placeholder) || "".html_safe
            else
              "".html_safe
            end
          else
            segment.placeholder
          end
        end

        # A forced :stream without the capability is a CONFIG mistake — warn
        # loudly but once per process (a deferred reply can fire per keystroke;
        # per-reply spam would bury the signal), then degrade to :fetch.
        def warn_stream_degraded
          return if @stream_degraded_warned

          @stream_degraded_warned = true
          return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

          ::Rails.logger.warn(
            "[phlex-reactive] defer_transport is :stream but the push lane is unavailable " \
            "(needs pgbus reactive Streams + SignedName + ActiveJob) — deferring via :fetch instead."
          )
        end
      end
    end
  end
end
