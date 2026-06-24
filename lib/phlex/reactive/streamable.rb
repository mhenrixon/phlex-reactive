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
          {model_param_name => model}.merge(options)
        end

        # Turbo::Streams::TagBuilder needs a real VIEW CONTEXT (it calls
        # `.formats` on it), not a controller class. Build one off-request from
        # the configured renderer controller. Memoized per class.
        def turbo_stream_builder
          ::Turbo::Streams::TagBuilder.new(turbo_view_context)
        end

        def turbo_view_context
          renderer.new.view_context
        end

        # Render a component to HTML with a full Rails view context. Routing
        # through the controller renderer keeps dom_id/url_for/t() working
        # during a re-render or broadcast.
        def render_component(component)
          renderer.render(component, layout: false)
        end

        def replace(model = nil, **options)
          component = build(model, options)
          turbo_stream_builder.replace(component.id, html: render_component(component))
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
        def broadcast_replace_to(*streamables, model: nil, exclude: nil, visible_to: nil, **options)
          component = build(model, options)
          ::Turbo::StreamsChannel.broadcast_replace_to(
            *streamables, target: component.id, html: render_component(component),
            **broadcast_transport_opts(exclude:, visible_to:)
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

        private

        def build(model, options)
          new(**(model ? component_args(model, options) : options))
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
      end

      # Required: the stable DOM id used as the Turbo Stream target. It MUST
      # match the id set on the component's root element in `view_template`.
      def id
        raise NotImplementedError, "#{self.class} must implement #id for Turbo Stream targeting"
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

      def to_stream_update
        self.class.turbo_stream_builder.update(id, html: self.class.render_component(self))
      end
    end
  end
end
