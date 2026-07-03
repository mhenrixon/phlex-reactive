# frozen_string_literal: true

module Phlex
  module Reactive
    # Streamable gives a self-contained Phlex component the ability to render
    # ITSELF as a Turbo Stream and to broadcast itself over a stream. Every
    # streamable component must implement `#id` returning a stable DOM id —
    # that id is the Turbo Stream target, so you never hand-pick targets.
    #
    # Class methods (use in controllers):
    #   render turbo_stream: Counter.replace(counter)
    #   render turbo_stream: [Row.append(target: "items", model: @item),
    #                         Totals.update(@order)]
    #
    # Broadcast methods (use in models/jobs/actions):
    #   Counter.broadcast_replace_to(counter, model: counter)
    #   Row.broadcast_append_to(@list, target: "items", model: @item)
    #
    # Convention: the `id` you set on the root element in `view_template` must
    # equal what `#id` returns, so replace/broadcast_replace target it.
    #
    # NOTE: we intentionally do NOT include Turbo::Streams::ActionHelper — it
    # pulls in ActionView::Helpers::TagHelper, which overrides Phlex's internal
    # `tag` method and breaks rendering. We use Turbo::Streams::TagBuilder
    # directly instead.
    module Streamable
      extend ActiveSupport::Concern

      # A per-thread cache entry: an off-request view context + the Turbo
      # TagBuilder bound to it, tagged with the renderer + generation it was
      # built for. Rebuilt on a thread when the renderer object changes or the
      # class generation is bumped — so a reset/reload/renderer-swap is picked
      # up without ever sharing a mutable context across threads.
      ThreadViewContext = Struct.new(:view_context, :builder, :renderer, :generation)

      # Focus ops are actor-only (they steal focus): broadcast_js_to rejects a
      # broadcast that carries one. Names mirror Phlex::Reactive::JS's focus verbs.
      BROADCAST_REFUSED_OPS = %w[focus focus_first].freeze

      # Every class that includes Streamable, so the engine can flush their
      # memoized view contexts on a Rails code reload (dev) in one pass. A
      # WeakMap used as a set (the class is the key) so a class reloaded by
      # Zeitwerk in dev is GC'd normally — a strong Array would pin every
      # reloaded generation and leak across reloads. Guarded by a mutex;
      # registration happens at class-load time, the reset iterates under lock.
      @registry = ObjectSpace::WeakMap.new
      @registry_mutex = Mutex.new

      class << self
        # Reset every streamable class's cached view context + builder. Called
        # from the engine's reloader (config.to_prepare) so a reloaded renderer
        # controller is never served from a stale memo. No-op outside Rails.
        def reset_all_view_contexts!
          @registry_mutex.synchronize do
            @registry.each_key(&:reset_turbo_view_context!)
          end
        end

        def register(klass)
          @registry_mutex.synchronize { @registry[klass] = true }
        end
      end

      included do
        Phlex::Reactive::Streamable.register(self)
      end

      class_methods do
        # The keyword the positional model maps to in `initialize`. For a
        # record-backed component (Component#reactive_record), this is the SAME
        # keyword the action endpoint uses in `from_identity` — so one
        # `initialize(<record>:)` satisfies BOTH the click path and the
        # broadcast path. Otherwise it falls back to the demodulized, underscored
        # class name (Invoice -> :invoice, InvoiceItem -> :invoice_item).
        # Override when it differs.
        def model_param_name
          if respond_to?(:reactive_record_key) && reactive_record_key
            reactive_record_key
          else
            name.demodulize.underscore.to_sym
          end
        end

        def component_args(model, options)
          { model_param_name => model }.merge(options)
        end

        # Turbo::Streams::TagBuilder needs a real VIEW CONTEXT (it calls
        # `.formats` on it), not a controller class. Build one off-request from
        # the configured renderer controller, bound to a real request so
        # request-dependent helpers (form_authenticity_token, host-aware URL
        # helpers) work during a re-render/broadcast (issue #42). Memoized PER
        # THREAD — building a
        # view context instantiates the renderer controller and assembles its
        # whole helper module set, so doing it per render/broadcast was the
        # hottest server-side allocation in the action round trip. The builder
        # is bound to that one context and reused too.
        #
        # Why per-thread and not one-per-process: an ActionView context carries
        # MUTABLE state (output_buffer/view_flow that #render_in's capture
        # swaps), so a single instance shared across threads can interleave or
        # bleed content between overlapping renders on a threaded server (Puma)
        # or in concurrent jobs. A thread-local cache keeps the amortization
        # (built once per thread, reused across that thread's renders) without
        # ever sharing a buffer across threads.
        def turbo_stream_builder
          thread_view_context_cache.builder
        end

        # The off-request view context for the current thread, built once and
        # reused. Rebuilt when the configured renderer object changes (a swap of
        # Phlex::Reactive.renderer) or when the class's view-context generation
        # is bumped (reset_turbo_view_context! / Rails code reload), so a
        # reloaded controller class is never served stale.
        def turbo_view_context
          thread_view_context_cache.view_context
        end

        # Invalidate the cached view context + builder for ALL threads by bumping
        # this class's generation — each thread rebuilds lazily on its next use,
        # and entries for the old generation are dropped. Registered on Rails'
        # reloader by the engine; also used by specs. Thread-safe (an integer
        # bump; no shared mutable structure to tear down).
        def reset_turbo_view_context!
          @turbo_view_context_generation = turbo_view_context_generation + 1
        end

        def turbo_view_context_generation
          @turbo_view_context_generation ||= 0
        end

        # Render a component to HTML with a full Rails view context. Uses
        # phlex-rails' #render_in against our memoized off-request view context
        # — a direct component.call that skips ActionController's renderer.render
        # machinery (TemplateRenderer, LookupContext, the render log subscriber):
        # ~2x faster with ~half the allocations, and byte-identical HTML. The
        # view context still carries the full Rails helper set, so
        # dom_id/url_for/t()/csrf keep working during a re-render or broadcast.
        def render_component(component)
          component.render_in(turbo_view_context)
        end

        # `morph: true` emits `<turbo-stream action="replace" method="morph">` so
        # Turbo 8's bundled Idiomorph morphs the subtree in place — preserving a
        # focused <input> + caret — instead of an outerHTML swap (issue #28).
        # Default (morph: false) is the unchanged plain replace.
        def replace(model = nil, morph: false, **options)
          component = build(model, options)
          turbo_stream_builder.replace(component.id, html: render_component(component), **morph_method(morph))
        end

        def update(model = nil, **options)
          component = build(model, options)
          turbo_stream_builder.update(component.id, html: render_component(component))
        end

        def append(target:, model: nil, **options)
          component = build(model, options)
          turbo_stream_builder.append(target, html: render_component(component))
        end

        def prepend(target:, model: nil, **options)
          component = build(model, options)
          turbo_stream_builder.prepend(target, html: render_component(component))
        end

        def remove(model = nil, **options)
          component = build(model, options)
          turbo_stream_builder.remove(component.id)
        end

        # --- Broadcasts (server -> client over the stream transport) ---
        # With pgbus installed, Turbo::StreamsChannel broadcasts route over
        # Postgres SSE instead of Action Cable, transactionally.
        #
        # Pass RAW key parts as *streamables (e.g. broadcast_append_to(@list, :items))
        # or (model, :symbol). Do NOT pass a pre-built stream key string — the
        # broadcaster builds the key itself, and double-keying can trip the
        # transport's separator guard.

        # `exclude:` / `visible_to:` are TRANSPORT options forwarded to the
        # stream (pgbus), not component init args. `exclude:` is the actor's
        # connection id — pass it to suppress the actor's own echo (the actor
        # already got the action's HTTP response). With Action Cable these are
        # ignored; with pgbus they reach the dispatcher. See docs/broadcasting.
        # `morph: true` makes the live cross-tab update morph in place (issue #28),
        # so a peer tab keeps its focus/caret on the morphed row. The broadcast
        # path takes EXTRA <turbo-stream> attributes via `attributes:` (not the
        # TagBuilder's `method:` kwarg), so the morph flag rides there.
        def broadcast_replace_to(*streamables, model: nil, exclude: nil, visible_to: nil, morph: false, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_replace_to(
            *streamables, target: component.id, html: render_component(component),
            **morph_attributes(morph), **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        def broadcast_update_to(*streamables, model: nil, exclude: nil, visible_to: nil, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_update_to(
            *streamables, target: component.id, html: render_component(component),
            **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        def broadcast_append_to(*streamables, target:, model: nil, exclude: nil, visible_to: nil, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_append_to(
            *streamables, target:, html: render_component(component),
            **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        def broadcast_prepend_to(*streamables, target:, model: nil, exclude: nil, visible_to: nil, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_prepend_to(
            *streamables, target:, html: render_component(component),
            **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        def broadcast_remove_to(*streamables, model: nil, exclude: nil, visible_to: nil, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_remove_to(
            *streamables, target: component.id,
            **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        # Push server-side client DOM ops to EVERY subscriber of a stream (issue
        # #97) — the broadcast sibling of Response#js. Rides a `reactive:js`
        # custom stream action over Turbo::StreamsChannel, so it works on Action
        # Cable AND pgbus (transport opts pass through broadcast_transport_opts
        # exactly like every other broadcast):
        #
        #   Notifications::Badge.broadcast_js_to(user, :alerts,
        #     js.add_class("#bell", "has-unread"), exclude: reactive_connection_id)
        #
        # `ops` is a Phlex::Reactive::JS chain (or a raw [[op, args], ...] array);
        # `target` (an element id) scopes op resolution on the client (nil →
        # document-scoped). The ops JSON is HTML-escaped through the TagBuilder's
        # attributes: path (data-reactive-ops), so a value can't break out of the
        # attribute.
        #
        # The builder REJECTS focus-class ops (focus/focus_first) outright:
        # broadcasting a focus steals focus in every subscriber's tab. Focus is an
        # actor-reply concern only (Response#js), so it raises ArgumentError here
        # rather than silently shipping a hostile-feeling broadcast.
        def broadcast_js_to(*streamables, ops, exclude: nil, visible_to: nil, target: nil)
          json = broadcast_js_ops_json(ops)
          ::Turbo::StreamsChannel.broadcast_action_to(
            *streamables,
            action: "reactive:js",
            target: target,
            attributes: { data: { reactive_ops: json } },
            render: false,
            **broadcast_transport_opts(exclude:, visible_to:)
          )
        end

        private

        # Validate + serialize broadcast ops: reject focus-class ops (they steal
        # focus in every tab) and an empty chain (a dead broadcast), then return
        # the JSON wire form. Works on a JS chain (inspect .ops) and a raw array.
        def broadcast_js_ops_json(ops)
          pairs = ops.is_a?(Phlex::Reactive::JS) ? ops.ops : Array(ops)
          refused = pairs.map { |name, _| name.to_s } & Phlex::Reactive::Streamable::BROADCAST_REFUSED_OPS
          unless refused.empty?
            raise ArgumentError,
              "broadcast_js_to refuses focus op(s) #{refused.join(", ")} — broadcasting focus " \
              "steals it in every subscriber's tab. Focus is an actor-reply concern (reply.js)."
          end

          Phlex::Reactive::Response.js_ops_json(ops)
        end

        def build(model, options)
          new(**(model ? component_args(model, options) : options))
        end

        # The TagBuilder (the .replace class builder + to_stream_morph) takes
        # `method: :morph` to emit the `method="morph"` attribute. Pass it ONLY
        # when morphing, so the default call produces today's plain replace.
        def morph_method(morph)
          morph ? { method: :morph } : {}
        end

        # The BROADCAST path renders extra <turbo-stream> attributes through
        # `attributes:` (it has no `method:` kwarg — that would fall into the
        # render args and be dropped). Same wire result: method="morph".
        def morph_attributes(morph)
          morph ? { attributes: { method: "morph" } } : {}
        end

        # Only include transport opts that were actually given, so on Action
        # Cable (which doesn't accept them) the common no-opts call is unchanged.
        def broadcast_transport_opts(exclude:, visible_to:)
          opts = {}
          opts[:exclude] = exclude unless exclude.nil?
          opts[:visible_to] = visible_to unless visible_to.nil?
          opts
        end

        def renderer
          Phlex::Reactive.renderer
        end

        def thread_view_context_cache
          store = (Thread.current[:phlex_reactive_view_contexts] ||= {})
          current = renderer
          generation = turbo_view_context_generation
          cached = store[self]

          unless cached && cached.renderer.equal?(current) && cached.generation == generation
            view_context = Phlex::Reactive.request_bound_view_context(current)
            cached = ThreadViewContext.new(
              view_context,
              ::Turbo::Streams::TagBuilder.new(view_context),
              current,
              generation
            )
            store[self] = cached
          end
          cached
        end
      end

      # The stable DOM id used as the Turbo Stream target. It MUST match the id
      # set on the component's root element in `view_template`.
      #
      # Record-backed components (Component's `reactive_record :x`) get a
      # default for free: dom_id(record) — the id virtually every such
      # component wrote by hand (issue #81). An explicit `def id` always wins
      # via normal method lookup. Everything else (state-backed, a bare
      # Streamable) still raises: a class-name default would silently collide
      # the moment two instances render on one page. Two DIFFERENT component
      # classes rendering the SAME record on one page also collide on the
      # default — give one a prefixed id: `def id = dom_id(@todo, "rich")`.
      #
      # Called on every render/stream build, so the default stays lean: a
      # respond_to? (reactive_record_key is Component API — a bare Streamable
      # keeps raising) plus ivar reads via the memoized reactive_record_ivar.
      def id
        klass = self.class
        if klass.respond_to?(:reactive_record_key) && (record_ivar = klass.reactive_record_ivar) &&
           (record = instance_variable_get(record_ivar))
          return dom_id(record)
        end

        raise NotImplementedError,
          "#{klass} must implement #id (the stable DOM id Turbo Streams target) — add e.g. " \
          "`def id = \"my-thing\"`. Record-backed components (reactive_record :x) get " \
          "`dom_id(record)` as the default automatically."
      end

      # Render-context-free dom_id, safe to use inside `#id`. The streamable
      # machinery calls `#id` BEFORE rendering, so Phlex's render-time `dom_id`
      # helper would raise HelpersCalledBeforeRenderError. This delegates to
      # ActionView::RecordIdentifier, which works anywhere — so
      # `def id = dom_id(@todo)` is safe.
      def dom_id(record, prefix = nil)
        ::ActionView::RecordIdentifier.dom_id(record, prefix)
      end

      # Render THIS already-built instance as a replace stream (used by the
      # reactive action endpoint after an action mutated state).
      def to_stream_replace
        self.class.turbo_stream_builder.replace(id, html: self.class.render_component(self))
      end

      # Render THIS instance as a MORPHING replace (issue #28):
      # `<turbo-stream action="replace" method="morph">`. Turbo 8's bundled
      # Idiomorph morphs the subtree in place — preserving the focused <input> +
      # caret across the re-render — while still carrying the root's fresh
      # data-reactive-token-value (so the signed token refreshes). Used by
      # Response.morph / Response.replace(self, morph: true).
      def to_stream_morph
        self.class.turbo_stream_builder.replace(id, html: self.class.render_component(self), method: :morph)
      end

      def to_stream_update
        self.class.turbo_stream_builder.update(id, html: self.class.render_component(self))
      end

      # Render a TOKEN-ONLY refresh stream (issue #30): a tiny
      # `<turbo-stream action="reactive:token">` carrying the component's fresh
      # signed token, with NO rendered body. It lets an action update only PART
      # of a component (its own hand-built streams) while still rolling the
      # signed identity token forward — the client reads the next token from this
      # attribute (#extractToken) and an inert client action writes it onto the
      # root (a pure attribute set, so a focused <input> + caret survive). Unlike
      # to_stream_replace, it does NOT re-render the children, so a live input
      # the user is typing into is never torn down. Used by Response.streams.
      #
      # The component carries its token via Component#reactive_token; a Streamable
      # that isn't a Component (no token) simply has nothing to refresh — guarded
      # by respond_to? so the primitive stays usable on a bare Streamable.
      #
      # respond_to? MUST include private methods (the `true` arg): Component
      # defines `reactive_token` as PRIVATE, so a plain `respond_to?(:reactive_token)`
      # is false for every Component and the stream silently carries an EMPTY token —
      # which makes any non-self-rendering reply (reply.streams #30, reply.append /
      # reply.remove #35) add-once-only: the first action works, then the stale (here
      # empty) token is rejected on the next dispatch (cosmos#1939). A bare Streamable
      # has no reactive_token method at all, so it still returns false correctly.
      def to_stream_token
        token = respond_to?(:reactive_token, true) ? reactive_token : nil
        %(<turbo-stream action="reactive:token" target="#{ERB::Util.html_escape(id)}" data-reactive-token-value="#{ERB::Util.html_escape(token)}"></turbo-stream>)
      end

      # Render THIS instance as a remove stream. The component already knows its
      # own #id, so no record/class reconstruction is needed (works for record-
      # and state-backed components alike). Used by Response.remove.
      def to_stream_remove
        self.class.turbo_stream_builder.remove(id)
      end
    end
  end
end
