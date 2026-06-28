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
      attr_reader :streams, :redirect_url, :token_component

      class << self
        # Re-render the component in place (explicit form of today's default).
        # `morph: true` morphs the subtree (preserves the focused input + caret)
        # instead of an outerHTML swap — see .morph (issue #28).
        def replace(component, morph: false)
          new(streams: [morph ? component.to_stream_morph : component.to_stream_replace])
        end

        # Re-render the component in place via Idiomorph (issue #28). Emits
        # `<turbo-stream action="replace" method="morph">`, so Turbo 8 morphs the
        # subtree — the focused <input> + caret survive the save. Use this for
        # per-field reactive editing (a "spreadsheet" grid where a debounced save
        # fires while the user is still typing/tabbing). The morphed root still
        # carries the fresh signed token, so the next action verifies.
        def morph(component) = new(streams: [component.to_stream_morph])

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

        # --- Reactive collections (issue #35) ---
        # Add/remove a row in a declared reactive_collection, emitting the row
        # stream + the count companion update + the empty-state toggle as ONE
        # Response. `component` is the bound CONTAINER (it carries the
        # declaration and the size resolver); `model` is the row's record (or, for
        # remove, a model OR a dom-id string). count/empty/size are optional — a
        # stream is emitted only for the pieces declared.
        #
        # render_self is false: the row append/prepend/remove IS the update, so
        # we must NOT also replace the whole container (that would re-render every
        # row and clobber the just-streamed delta).
        #
        # token_component is the CONTAINER (cosmos#1939): a reply that does NOT
        # re-render self must STILL refresh self's signed token, or the list is
        # add-once-only — correct on the first click, then every subsequent dispatch
        # from the list root is rejected (its token went stale) with no error. The
        # container owns the add/remove trigger, so the endpoint appends its inert
        # `reactive:token` stream (the same #30 machinery reply.streams uses) to roll
        # the token forward without re-rendering the rows.
        def collection_append(component, name, model)
          definition = collection_def!(component, name)
          new(streams: collection_add_streams(definition, component, model, :append),
            render_self: false, token_component: component)
        end

        def collection_prepend(component, name, model)
          definition = collection_def!(component, name)
          new(streams: collection_add_streams(definition, component, model, :prepend),
            render_self: false, token_component: component)
        end

        def collection_remove(component, name, model)
          definition = collection_def!(component, name)
          new(streams: collection_remove_streams(definition, component, model),
            render_self: false, token_component: component)
        end

        private

        # Resolve the declaration off the container's class, raising a clear error
        # for an undeclared name (a typo'd collection should fail loudly, not
        # silently emit an empty Response).
        def collection_def!(component, name)
          component.class.reactive_collection_def(name) ||
            raise(Phlex::Reactive::Error, "undeclared reactive_collection :#{name} on #{component.class}")
        end

        # Row add (append/prepend) + count + empty-state clear. The empty-state is
        # removed only when the list just crossed 0->1 (size == 1) — appending to
        # an already-populated list leaves it untouched.
        def collection_add_streams(definition, component, model, action)
          streams = [definition.item.public_send(action, target: definition.container, model:)]
          append_count_stream(streams, definition, component)

          size = definition.size_for(component)
          if definition.empty && size == 1
            streams << definition.empty.new.to_stream_remove
          end
          streams
        end

        # Row remove + count + empty-state restore. The empty-state is appended
        # back into the container only when the list just emptied (size == 0).
        def collection_remove_streams(definition, component, model)
          streams = [collection_row_remove(definition, model)]
          append_count_stream(streams, definition, component)

          size = definition.size_for(component)
          if definition.empty && size&.zero?
            # Render the empty-state and append it INTO the container (not its
            # own id) — restoring "No items yet" when the last row was removed.
            # model: nil builds it argument-free (an empty-state is a static view).
            streams << definition.empty.append(target: definition.container, model: nil)
          end
          streams
        end

        # Remove the row by its DOM id. Accepts the record (so dom_id is derived)
        # or an already-built dom-id string (e.g. the value the row used as #id).
        def collection_row_remove(definition, model)
          if model.is_a?(String)
            Phlex::Reactive.flash_builder.remove(model)
          else
            definition.item.remove(model)
          end
        end

        # Append the count companion's update stream when a count id + a size
        # resolver are both declared. The size is a number, HTML-escaped by Turbo.
        def append_count_stream(streams, definition, component)
          return unless definition.count

          size = definition.size_for(component)
          return if size.nil?

          streams << update_stream(definition.count, size.to_s)
        end

        public

        # Partial / per-field update with a TOKEN-ONLY refresh (issue #30). Emits
        # EXACTLY the given streams — no forced full-self replace — but binds
        # `component` so the endpoint appends its tiny `to_stream_token` stream.
        # So the signed token rolls forward (the next action verifies) while the
        # component's own live inputs are never torn down: ideal for a
        # spreadsheet-like grid where a debounced save re-streams only a total
        # cell and the user is still typing in a sibling field.
        #
        #   Response.streams(self, Totals.update(@invoice))   # update only the totals
        #
        # render_self is false (we do NOT inject the full replace); the token is
        # refreshed by the bound component's token stream instead.
        def streams(component, *strings)
          new(streams: strings.flatten, render_self: false, token_component: component)
        end

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
      #
      # token_component: set by .streams (issue #30) — a partial update that opts
      # OUT of the full-self replace but still needs the token refreshed. The
      # endpoint appends this component's tiny to_stream_token instead, so the
      # token rolls forward without re-rendering (and clobbering) the children.
      def initialize(streams: [], redirect_url: nil, render_self: true, token_component: nil)
        @streams = streams.freeze
        @redirect_url = redirect_url
        @render_self = render_self
        @token_component = token_component
        freeze
      end

      # Append extra turbo-stream strings (a sibling component, a flash).
      # Returns a NEW Response (immutable).
      def stream(*more)
        self.class.new(
          streams: @streams + more.flatten,
          redirect_url: @redirect_url,
          render_self: @render_self,
          token_component: @token_component
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
      # `morph: true` morphs the companion in place (issue #28) — use it when the
      # companion also holds focusable inputs that must survive the re-render.
      def also_replace(component, morph: false)
        stream(morph ? component.to_stream_morph : component.to_stream_replace)
      end

      def redirect? = !@redirect_url.nil?
      def render_self? = @render_self

      # True when a partial update (.streams) opted out of the full-self replace
      # but still needs the token rolled forward — the endpoint appends the bound
      # component's tiny token-only stream (issue #30).
      def refresh_token? = !@token_component.nil?
    end
  end
end
