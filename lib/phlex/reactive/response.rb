# frozen_string_literal: true

module Phlex
  module Reactive
    # An explicit, immutable description of the ACTOR's HTTP response to a
    # reactive action. An action MAY return one; if it returns anything else
    # (the legacy contract — return value ignored), the endpoint falls back to
    # the implicit single component.to_stream_replace.
    #
    # A Response governs ONLY the actor's HTTP reply. Cross-tab updates still go
    # through Streamable's broadcast_*_to(..., exclude: reactive_connection_id).
    #
    #   Response.replace(self)                          # re-render in place (the default, explicit)
    #   Response.replace(self).flash(:error, msg)       # surface a validation error
    #   Response.replace(self).also_update("heading", html: @record.name)  # + a companion element
    #   Response.remove(self)                           # drop the element (e.g. moderation queue)
    #   Response.redirect(article_url(@article))        # slug changed -> Turbo.visit the new URL
    #   Response.replace(self).stream(Totals.update(@order))  # multi-stream
    class Response
      attr_reader :streams, :redirect_url

      class << self
        # Re-render the component in place (explicit form of today's default).
        def replace(component) = new(streams: [component.to_stream_replace])

        # Morph only inner HTML (preserves the root element + its token attr).
        def update(component) = new(streams: [component.to_stream_update])

        # Remove the component's element from the DOM. Uses the instance
        # to_stream_remove (the component already knows its own #id — no
        # class-builder reconstruction; works for record- and state-backed).
        def remove(component) = new(streams: [component.to_stream_remove], render_self: false)

        # Client-side full navigation (Turbo.visit). Use when the current URL
        # is dead (slug rename) or the outcome belongs on another page. Pass a
        # *_url (the off-request render context has no request host for *_path).
        def redirect(url) = new(redirect_url: url, render_self: false)

        # Escape hatch / multi-stream root: zero or more raw turbo-stream strings.
        def with(*strings) = new(streams: strings.flatten)

        # Build a flash turbo-stream that appends `content` into a host-app
        # container. `content` is a Phlex component instance (rendered through
        # the configured renderer so t()/url_for work) or a ready HTML string —
        # supplied by the caller because the render context is off-request
        # (there is no Rails `flash`).
        def flash_stream(_level, content, target:)
          Phlex::Reactive.flash_builder.append(target, html: render_html(content))
        end

        # Build a turbo-stream that updates an arbitrary target id with `content`
        # (a Phlex component instance or an HTML string). Used by #also_update to
        # re-render a companion element that isn't itself a Streamable component.
        def update_stream(target, content)
          Phlex::Reactive.flash_builder.update(target, html: render_html(content))
        end

        # Resolve `content` to the HTML for a turbo-stream's `html:`. Two forms,
        # both SAFE against injection by default:
        #   * a Phlex component instance — rendered through the configured
        #     renderer, which auto-escapes interpolated values.
        #   * any other value — coerced with to_s and handed to Turbo's
        #     TagBuilder, which HTML-ESCAPES a plain String. So a model value
        #     (`html: @record.name`) cannot inject markup. To emit intentional
        #     raw HTML, pass an `html_safe` String (Turbo leaves those verbatim)
        #     or a Phlex component. Same contract as the pre-existing flash_stream.
        def render_html(content)
          content.is_a?(::Phlex::SGML) ? Phlex::Reactive.render(content) : content.to_s
        end
      end

      # render_self: when true (default for replace/update/with), the endpoint
      # GUARANTEES the component's own replace is present so its
      # data-reactive-token-value refreshes (the client extracts the next token
      # from the response HTML). remove/redirect set it false (nothing stays).
      def initialize(streams: [], redirect_url: nil, render_self: true)
        @streams = streams.freeze
        @redirect_url = redirect_url
        @render_self = render_self
        freeze
      end

      # Append extra turbo-stream strings (a sibling component, a flash).
      # Returns a NEW Response (immutable).
      def stream(*more)
        self.class.new(
          streams: @streams + more.flatten,
          redirect_url: @redirect_url,
          render_self: @render_self
        )
      end

      # Append a flash turbo-stream into a host-app container (default
      # <div id="flash">, configurable via Phlex::Reactive.flash_target).
      def flash(level, content, target: Phlex::Reactive.flash_target)
        stream(self.class.flash_stream(level, content, target:))
      end

      # Also re-render a COMPANION element alongside self — a page heading, a
      # summary card, a badge that recomputes from the saved value (issue #25).
      # `target` is the sibling element's DOM id. `html` is either:
      #   * a plain String — HTML-ESCAPED by Turbo, so a model value is safe:
      #       Response.replace(self).also_update("page_heading", html: @record.name)
      #   * a Phlex component — rendered + auto-escaped through the renderer (use
      #     this when the companion has its own markup), or an `html_safe` String
      #     for intentional raw HTML.
      # Returns a NEW Response (immutable). The common "re-render self + N
      # siblings" case no longer needs raw turbo_stream_builder.
      def also_update(target, html:)
        stream(self.class.update_stream(target, html))
      end

      # Like #also_update, but renders ANOTHER Streamable component and replaces
      # it by its own #id — for a companion that is itself a component.
      #   Response.replace(self).also_replace(SummaryCard.new(order: @order))
      def also_replace(component)
        stream(component.to_stream_replace)
      end

      def redirect? = !@redirect_url.nil?
      def render_self? = @render_self
    end
  end
end
