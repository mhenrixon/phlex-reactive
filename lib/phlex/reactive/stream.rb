# frozen_string_literal: true

module Phlex
  module Reactive
    # A Turbo Stream that IS an html_safe String — it drops into
    # `render turbo_stream:`, ERB/Phlex interpolation, and Turbo test-helper
    # substring asserts unchanged — but ALSO carries the structural facts the
    # action endpoint needs: `rx_action`, `rx_target`, `rx_renders_root?`, and a
    # token flag computed ONCE from ground truth (the html bytes).
    #
    # WHY (issue #114): the endpoint used to reverse-engineer turbo-stream
    # SEMANTICS out of MARKUP — substring-scanning every stream for
    # `data-reactive-token-value` and regexing the opening tag's `action="..."`
    # against a self-render allowlist. The gem was parsing strings it just built,
    # and every new stream shape needed a new patch to the heuristics. A Stream
    # knows its action, target, and token-ness at CONSTRUCTION, so the endpoint
    # reads fields instead of scanning markup.
    #
    # Subclasses ActiveSupport::SafeBuffer deliberately. The sole thing
    # `render turbo_stream: [s1, s2]` does to each element is `plain_string << s`
    # (verified against actionpack 8.1.3 / turbo-rails 2.0.23: the renderer
    # returns the array unchanged, Response#body= stores it, and Buffer#body does
    # `buf = +""; each { |chunk| buf << chunk }`). `String#<<` needs `#to_str`,
    # which a SafeBuffer subclass inherits — so the ivars ride to the wire and
    # the bytes are byte-identical to today's TagBuilder output. Being IS-A-String
    # also satisfies every public-API interop requirement (clause 2) for free.
    #
    # Metadata-loss is a FEATURE, not a bug. `dup`/`+` keep the class + ivars, so
    # they stay on the structural path with accurate fields (the bytes are
    # unchanged). `gsub`/interpolation/`*` reshape the bytes and return a plain
    # String/SafeBuffer — precisely when the object is no longer a
    # structurally-known stream and SHOULD be treated as opaque. The endpoint's
    # `is_a?(Stream) && rx_action` guard turns every such loss into the SAFE
    # legacy regex path. INVARIANT: never `+`/`gsub`/`<<` a built Stream and keep
    # using it as a Stream — re-`wrap` the result to recompute the flags.
    class Stream < ActiveSupport::SafeBuffer
      # The attribute the client's #extractToken reads. Its PRESENCE (by name) is
      # what "carries a token" means — the same contract the old substring scan
      # used, so an accidentally-empty token still flags true (not a regression;
      # the real cosmos#1939 guard lives upstream in #to_stream_token).
      TOKEN_ATTR = "data-reactive-token-value"

      # Actions whose OPENING tag re-renders the component's OWN root, so the
      # root's fresh token rolls the signed identity forward. `append`/`prepend`
      # insert CHILDREN and are deliberately excluded (issue #44): a child row's
      # token embedded in an append `<template>` must NEVER count as the
      # container's refresh. `reactive:token` is our inert token-only refresh.
      SELF_RENDER_ACTIONS = %w[replace update reactive:token].freeze

      class << self
        # The single construction seam every builder routes its already-html_safe
        # output through. `html` MUST already be html_safe (a TagBuilder result or
        # an explicitly `.html_safe` string) — we do NOT escape, so the wire stays
        # byte-identical. `renders_root` is set STRUCTURALLY by the builder that
        # knows its own semantics; `carries_token` is GROUND TRUTH.
        def wrap(html, action:, target:, renders_root:)
          new(html.to_s, action: action, target: target, renders_root: renders_root)
        end
      end

      def initialize(html = "", action: nil, target: nil, renders_root: false)
        super(html) # SafeBuffer copies the bytes verbatim — byte-identical wire.
        @rx_action = action&.to_s
        @rx_target = target&.to_s
        @rx_renders_root = renders_root ? true : false
        # ONE O(bytes) scan at BUILD time — the ground-truth token flag. A
        # `with(...)` raw string that omits the token and a replace whose render
        # happened to include one both answer honestly; the flag is NEVER
        # inferred from `action` (that would reintroduce cosmos#1939).
        @rx_carries_token = include?(TOKEN_ATTR)
        freeze # an immutable value object
      end

      attr_reader :rx_action, :rx_target

      def rx_renders_root? = @rx_renders_root
      def rx_carries_token? = @rx_carries_token

      # Does THIS stream ALREADY refresh `component_target`'s signed token by
      # re-rendering its own root? Purely structural — replaces the two-method
      # opening-tag regex (carries_token_for? + self_render_stream_for?). All must
      # hold: it carries a token AND re-renders the root AND targets THIS
      # component AND the action is a self-render action.
      #   * A sibling replace (different target) → false, so ours still refreshes
      #     (issue #30).
      #   * An appended child row (renders_root false) → false, so the container's
      #     token still refreshes even though the row embeds its own (issue #44).
      # `component_target` is the RAW dom id (never the escaped `target="..."`
      # attribute); escaping happens only in the emitted HTML.
      def rx_refreshes_token_for?(component_target)
        @rx_carries_token &&
          @rx_renders_root &&
          @rx_target == component_target.to_s &&
          SELF_RENDER_ACTIONS.include?(@rx_action)
      end
    end
  end
end
