# frozen_string_literal: true

require "zeitwerk"
require "globalid"

# VERSION is a plain constant, not a Zeitwerk-managed file (it defines VERSION,
# not Version). Require it up front and ignore the file below so the loader
# never tries to load it — otherwise eager_load_all (host app with
# config.eager_load = true) raises Zeitwerk::NameError.
require_relative "reactive/version"

module Phlex
  # phlex-reactive: reactive Phlex components for Rails.
  #
  # Two cooperating mixins, one client runtime, one endpoint:
  #
  #   * Phlex::Reactive::Streamable — gives a component a stable `id` and class
  #     methods to render itself as a Turbo Stream (`.replace`, `.append`, ...)
  #     and to broadcast itself (`.broadcast_replace_to`, ...). The server->client
  #     half (controller responses + background broadcasts).
  #
  #   * Phlex::Reactive::Component — declares client-invokable `action`s and
  #     emits a signed identity token + the wiring the generic `reactive`
  #     Stimulus controller needs. The client->server half (clicks, form input).
  #
  # Both halves converge on ONE re-render unit: the component, targeted by its
  # `id`. See the README for the mental model and examples.
  module Reactive
    class Error < StandardError; end

    # Raised when a signed identity token fails verification (tampered, expired,
    # or signed with a different key) — or when a verified token names a class
    # that doesn't resolve to a reactive component. `diagnostic` classifies the
    # cause (:tampered, :unknown_class, :not_reactive_class) so the endpoint can
    # render a verbose_errors body explaining WHICH failure this was.
    class InvalidToken < Error
      attr_reader :diagnostic

      def initialize(msg = nil, diagnostic: nil)
        @diagnostic = diagnostic
        super(msg)
      end
    end

    # Purpose string bound into every identity token's signature so a token
    # minted for phlex-reactive can't be replayed against another verifier use.
    IDENTITY_PURPOSE = "phlex-reactive/identity"

    class << self
      # The message verifier used to sign/verify component identity tokens.
      # Defaults to a purpose-scoped verifier derived from secret_key_base.
      # Override to use a dedicated key.
      attr_writer :verifier

      # The controller class used to render components with a full Rails view
      # context (url helpers, CSRF, i18n) during re-renders and broadcasts.
      # Defaults to ActionController::Base. Set to your ApplicationController if
      # components rely on app-level helpers or Current attributes.
      attr_writer :renderer

      # The controller the reactive ActionsController inherits from, given as a
      # String (resolved lazily to avoid load-order issues). Defaults to
      # "ActionController::Base"; set to "ApplicationController" to inherit your
      # app's auth/CSRF/Current. If you do, ensure the action path isn't
      # force-redirected for logged-out users when you have public components.
      attr_writer :base_controller_name

      # Exception classes the action endpoint renders as 403. Append your
      # authorization library's error (Pundit::NotAuthorizedError,
      # ActionPolicy::Unauthorized, ...).
      attr_accessor :authorization_errors

      # The path the action endpoint is mounted at. Default "/reactive/actions".
      # Set before boot if it collides with an app route. The client runtime
      # reads it from a <meta name="phlex-reactive-action-path"> tag if present,
      # falling back to this default.
      attr_writer :action_path

      def action_path
        @action_path ||= "/reactive/actions"
      end

      # Diagnostic endpoint error bodies + dropped-param logging. When true, an
      # endpoint failure (400/403/404) carries a plain-text explanation body
      # (the client already console.errors it) and param coercion warn-logs
      # every dropped key with its bracketed path and reason. Statuses never
      # change with the flag, and the endpoint's warn log fires regardless.
      #
      # Defaults LAZILY to Rails.env.local? — that's development AND test — so
      # production stays opaque unless you opt in. The `defined?` guard (not
      # `||=`) makes an explicit `= false` stick even in dev/test.
      attr_writer :verbose_errors

      def verbose_errors
        return @verbose_errors if defined?(@verbose_errors)

        defined?(::Rails.env) && ::Rails.env.local?
      end

      def verifier
        @verifier ||= default_verifier
      end

      def renderer
        @renderer ||= defined?(::ActionController::Base) ? ::ActionController::Base : nil
      end

      # Build an off-request view context whose controller has a REAL `request`.
      #
      # A bare `controller.new.view_context` (the naive off-request context) has
      # `request == nil`, so any request-dependent helper raises
      # `undefined method 'env' for nil` — form_authenticity_token,
      # protect_against_forgery?, and host-aware URL helpers all read
      # `request.env` (issue #42). We replicate exactly what
      # ActionController::Renderer#render does to set up its mock request — build
      # an ActionDispatch::Request from the renderer's env (which derives the host
      # from the routes' default_url_options), bind the routes, and attach it —
      # then return the controller's view context instead of rendering a template.
      # The result keeps the 0.4.0 render_in speedup (no renderer.render
      # machinery) while restoring the request those helpers need.
      def request_bound_view_context(controller_class)
        ar_renderer = controller_class.renderer
        request = ::ActionDispatch::Request.new(ar_renderer.send(:env_for_request))
        request.routes = controller_class._routes

        instance = controller_class.new
        instance.set_request!(request)
        instance.set_response!(controller_class.make_response!(request))
        instance.view_context
      end

      # DOM id of the host-app container a Response#flash appends into.
      # Default "flash"; override to match your layout's flash region.
      def flash_target
        @flash_target ||= "flash"
      end

      attr_writer :flash_target

      # Component class used to render STRING flash content (issue #77).
      # Instantiated as flash_component.new(level:, content:) and rendered
      # through the existing render path, replacing the built-in
      # <div class="reactive-flash reactive-flash--{level}"> wrapper. Default
      # nil (the built-in wrapper). Phlex component content passed to
      # reply.flash always renders verbatim and bypasses this.
      attr_accessor :flash_component

      # Render a Phlex component to HTML with a full (off-request) view context.
      # Uses phlex-rails' #render_in against the memoized view context — a direct
      # component.call that skips ActionController's renderer.render machinery
      # (~2x faster, ~half the allocations), with the same HTML and full helper
      # access (dom_id/url_for/t/csrf). Used for a Phlex component embedded as
      # Response#with content.
      def render(component)
        component.render_in(off_request_view_context)
      end

      # A Turbo::Streams::TagBuilder bound to an off-request view context, used
      # to build standalone streams (e.g. a Response flash append) not tied to a
      # specific component's id. Cached PER THREAD alongside the context it's
      # bound to (see off_request_view_context for why per-thread).
      def flash_builder
        off_request_view_context_cache[:builder]
      end

      # The off-request view context for the current thread, built once and
      # reused for both the flash builder and standalone component renders.
      # Cached PER THREAD, not per process: an ActionView context carries mutable
      # output_buffer/view_flow state (render_in's capture swaps it), so sharing
      # one instance across threads can interleave content on a threaded server.
      # Rebuilt when the renderer object changes or the generation is bumped
      # (reset_flash_builder! / Rails code reload), so a reloaded controller is
      # never served stale.
      def off_request_view_context
        off_request_view_context_cache[:view_context]
      end

      # Invalidate the per-thread context + builder for ALL threads by bumping
      # the generation; each thread rebuilds lazily on next use. Registered on
      # Rails' reloader by the engine; also used by specs. Thread-safe (an
      # integer bump, no shared structure to tear down).
      def reset_flash_builder!
        @off_request_view_context_generation = off_request_view_context_generation + 1
      end

      def off_request_view_context_generation
        @off_request_view_context_generation ||= 0
      end

      private

      def off_request_view_context_cache
        cache = Thread.current[:phlex_reactive_off_request_view_context]
        current = renderer
        generation = off_request_view_context_generation

        unless cache && cache[:renderer].equal?(current) && cache[:generation] == generation
          view_context = request_bound_view_context(current)
          cache = {
            view_context: view_context,
            builder: ::Turbo::Streams::TagBuilder.new(view_context),
            renderer: current,
            generation: generation
          }
          Thread.current[:phlex_reactive_off_request_view_context] = cache
        end
        cache
      end

      public

      def base_controller_name
        @base_controller_name ||= "ActionController::Base"
      end

      def base_controller
        base_controller_name.constantize
      end

      # Returns the verified payload hash, or nil if the token is invalid.
      def verify(token)
        verifier.verified(token, purpose: IDENTITY_PURPOSE)
      end

      # Signs a payload hash into an identity token.
      def sign(payload)
        verifier.generate(payload, purpose: IDENTITY_PURPOSE)
      end

      # The acting client's SSE connection id during an action, or nil. Set by
      # the ActionsController from the X-Pgbus-Connection header. A component
      # action passes `exclude: Phlex::Reactive.current_connection_id` (or the
      # `reactive_connection_id` helper) to suppress the actor's own broadcast
      # echo.
      def current_connection_id
        Thread.current[:phlex_reactive_connection_id]
      end

      def with_connection_id(connection_id)
        previous = Thread.current[:phlex_reactive_connection_id]
        Thread.current[:phlex_reactive_connection_id] = connection_id.presence
        yield
      ensure
        Thread.current[:phlex_reactive_connection_id] = previous
      end

      # The controller a correctly-mounted action path resolves to. Used by the
      # route guard below.
      ACTIONS_CONTROLLER = "phlex/reactive/actions"

      # True when a POST to `path` resolves to the gem's ActionsController. A host
      # catch-all route (match "*path", ...) appended above the engine's route
      # SHADOWS it, so every reactive POST 404s and none of the controller runs —
      # the opaque "is the endpoint even mounted?" failure (issue #26). A false
      # here is the signal. Returns false (not raise) when nothing matches.
      def action_route_ok?(path = action_path)
        return false unless defined?(::Rails) && ::Rails.application

        # At after_initialize (when the boot guard runs) the host's routes may not
        # be drawn yet, so recognize_path would see an incomplete set and report a
        # false shadow. Force-load routes first (idempotent — no-op if already
        # loaded), so the check is correct whether it runs at boot or at runtime.
        ensure_routes_loaded
        recognized = ::Rails.application.routes.recognize_path(path, method: :post)
        recognized[:controller] == ACTIONS_CONTROLLER
      rescue ActionController::RoutingError, ActiveRecord::RecordNotFound
        false
      end

      # Log a clear warning (once, at boot) when the action path doesn't resolve
      # to the gem controller — pointing at the catch-all shadow rather than
      # leaving an adopter to guess. Called from the engine's after_initialize.
      def warn_unless_action_route_mounted!(path: action_path, logger: default_logger)
        return if action_route_ok?(path)
        return unless logger

        logger.warn(
          "[phlex-reactive] POST #{path} does not resolve to #{ACTIONS_CONTROLLER}. " \
          "A host catch-all route (e.g. match \"*path\", ...) likely shadows it, so reactive " \
          "actions will 404. Exempt #{path.delete_prefix("/")} from the catch-all, or set " \
          "Phlex::Reactive.action_path to an unshadowed path. See the README integration section."
        )
      end

      private

      # Materialize the route set if it hasn't been drawn yet (the engine appends
      # POST /reactive/actions when routes are drawn, which may be after the boot
      # guard's after_initialize). Idempotent; tolerant of older Rails.
      def ensure_routes_loaded
        reloader = ::Rails.application.routes_reloader
        if reloader.respond_to?(:execute_unless_loaded)
          reloader.execute_unless_loaded
        elsif ::Rails.application.respond_to?(:reload_routes_unless_loaded)
          ::Rails.application.reload_routes_unless_loaded
        end
      end

      def default_logger
        ::Rails.logger if defined?(::Rails) && ::Rails.respond_to?(:logger)
      end

      def default_verifier
        unless defined?(::Rails) && ::Rails.application
          raise Error, "Phlex::Reactive.verifier is unset and Rails.application is unavailable; " \
                       "set Phlex::Reactive.verifier = ActiveSupport::MessageVerifier.new(secret)"
        end

        ::Rails.application.message_verifier(IDENTITY_PURPOSE)
      end
    end

    self.authorization_errors = []
  end
end

loader = Zeitwerk::Loader.new
loader.tag = "phlex-reactive"
# Root is lib/ so files map to the Phlex::Reactive namespace
# (lib/phlex/reactive/foo.rb -> Phlex::Reactive::Foo).
lib = File.expand_path("..", __dir__)
loader.push_dir(lib)
# The gem-name shim (`require "phlex-reactive"`) is a plain require, not a
# managed file.
loader.ignore("#{lib}/phlex-reactive.rb")
# version.rb defines VERSION (a constant, not a `Version` class) and is required
# above — Zeitwerk must not try to load it.
loader.ignore("#{lib}/phlex/reactive/version.rb")
# Rails generators are discovered and loaded by Rails' own generator system,
# not the app autoloader. Their path/constant scheme
# (generators/phlex/reactive/... defining Phlex::Reactive::Generators::...)
# deliberately doesn't follow Zeitwerk's rules, so the loader must ignore them.
loader.ignore("#{lib}/generators")
# The engine is required explicitly below (only when Rails is present) and must
# not be eager-loaded before that.
loader.do_not_eager_load("#{__dir__}/reactive/engine.rb")
loader.setup

require "phlex/reactive/engine" if defined?(Rails::Engine)
