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

    # Raised at DECLARATION time (Component.action -> ParamSchema.compile) when a
    # param schema names a type symbol that isn't in the registry — a typo like
    # `params: { count: :interger }`. A stdlib ArgumentError subclass (NOT a
    # NameError): the mistake is a bad ARGUMENT to `action`, and callers rescue
    # ArgumentError, not NameError, for a bad-input contract. Loud at class load
    # (eager loading in production; first constant reference under Zeitwerk dev)
    # instead of a silent `to_s` at request time.
    #
    # Superclass is fully qualified `::ArgumentError`: the phlex gem defines
    # Phlex::ArgumentError, and a bare `ArgumentError` here resolves LEXICALLY to
    # that (Phlex::Reactive -> Phlex), coupling us to a Phlex error rather than
    # the stdlib one an app catches.
    class UnknownParamType < ::ArgumentError; end

    # Purpose string bound into every identity token's signature so a token
    # minted for phlex-reactive can't be replayed against another verifier use.
    IDENTITY_PURPOSE = "phlex-reactive/identity"

    # Purpose string for DEFER tokens (issue #165) — the short-TTL identity a
    # reply.defer directive carries so the client can fetch the expensive
    # render off the actor's critical path. A distinct purpose makes the two
    # token families non-interchangeable BY SIGNATURE: an action token is
    # rejected at the defer endpoint (it must not become a render oracle) and a
    # defer token can never invoke an action (it carries no action grant).
    DEFER_PURPOSE = "phlex-reactive/defer"

    # The defer_transport values (issue #165): :auto picks push (pgbus durable
    # one-shot stream + ActiveJob) when capable, else pull (parallel fetch);
    # :fetch forces pull; :stream requests push but still degrades to pull with
    # a warning when the capability is absent (degrade, never break).
    DEFER_TRANSPORTS = %i[auto fetch stream].freeze

    # The current identity-token payload version (issue #111), stamped into every
    # signed token under the "v" key. It exists so the NEXT breaking shape change
    # (a rename, per-token expiry, a nonce) can upgrade tokens already in flight
    # instead of breaking every open page at deploy. A token minted before this
    # existed carries no "v" — treated as version 0 (today's shape). Bump this and
    # register a register_token_upgrader(old_version) when you change the shape.
    TOKEN_VERSION = 1

    # The ActiveSupport::Notifications namespace for the gem's hot-path events
    # (issue #107): action.phlex_reactive, render.phlex_reactive,
    # broadcast.phlex_reactive. APM tools (AppSignal, Datadog, Skylight)
    # auto-subscribe to `*.phlex_reactive` and get component-level visibility.
    # Payloads carry NAMES/outcome/sizes ONLY — never the token, params, or state.
    INSTRUMENTATION_NAMESPACE = "phlex_reactive"

    # What a component-aware around_action wrapper sees (issue #112). Frozen: a
    # wrapper OBSERVES the resolved action — it must not mutate the context to
    # widen invokability (the token verify, component resolution, default-deny,
    # and schema coercion have already run and are not negotiable here).
    #   * component    — the resolved, identity-rebuilt component instance
    #   * action_name  — the declared action Symbol about to run
    #   * params       — the SCHEMA-COERCED params (dropped keys already gone)
    #   * request      — the ActionDispatch::Request (remote_ip, headers, ...)
    ActionContext = Data.define(:component, :action_name, :params, :request)

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

      # Attach the opt-in LogSubscriber (issue #107) so each hot-path event is
      # debug-logged as one compact line (`[reactive] Counter#increment ok
      # (3.1ms)`). Default OFF — the events still fire for APMs regardless; this
      # only controls the gem's own log lines. The engine reads it at boot and
      # attaches exactly once. Set true in an initializer to see the lines.
      attr_writer :log_events

      def log_events
        return @log_events if defined?(@log_events)

        false
      end

      # Client debug mode (issue #108): the "devtools-lite" lens on the reactive
      # round trip. When true, reactive_attrs (and so reactive_root) stamps
      # data-reactive-debug="true" on the root, and the generic controller
      # console.groups every dispatch — action, param/collected NAMES (never
      # values), request encoding, HTTP status, the response's stream actions +
      # targets, whether a token refresh arrived (never the token VALUE), and the
      # round-trip ms. Default OFF (the initializer template suggests
      # Rails.env.development?); zero cost when off (one nil-check per dispatch, no
      # attr, no string building). The `defined?` guard (not `||=`) makes an
      # explicit `= false` stick even where a truthy default might otherwise apply.
      attr_writer :debug

      def debug
        return @debug if defined?(@debug)

        false
      end

      # Register an app-defined param type (issue #109). The block receives the
      # raw client value and returns the coerced value — or Phlex::Reactive::
      # ParamSchema::DROP to reject it (the keyword default then applies, keeping
      # the drop-don't-fabricate contract). Register in an INITIALIZER: the
      # registry is frozen after boot (freeze_param_types!), so a runtime
      # registration raises, and a schema referencing the type is validated at
      # declaration.
      #
      #   # config/initializers/phlex_reactive.rb
      #   Phlex::Reactive.param_type(:money) do |v|
      #     /\A\d+(\.\d{1,2})?\z/.match?(v.to_s) ? BigDecimal(v) : Phlex::Reactive::ParamSchema::DROP
      #   end
      #   # then: action :charge, params: { amount: :money }
      def param_type(name, &block)
        raise ::ArgumentError, "Phlex::Reactive.param_type requires a block" unless block

        if param_types_frozen?
          raise Error, "Phlex::Reactive.param_type(#{name.inspect}) called after boot — the param-type " \
                       "registry is frozen once the app is initialized. Register custom param types in an " \
                       "initializer (config/initializers/phlex_reactive.rb)."
        end

        param_types[name.to_sym] = block
      end

      # The param-type registry: Symbol => callable(value) -> coerced | DROP.
      # Seeded lazily with the built-ins; ParamSchema.compile validates every
      # declared type symbol against it, and #coerce dispatches through it.
      def param_types
        @param_types ||= Phlex::Reactive::ParamSchema.built_in_types.dup
      end

      # A declared type symbol is known iff it's a registry key. ParamSchema
      # asks this at compile so an unknown symbol raises loudly at declaration.
      def param_type?(name)
        param_types.key?(name.to_sym)
      end

      # Freeze the registry so no further param_type registration is accepted —
      # the initializer-only contract. Called by the engine's after_initialize.
      # Idempotent.
      def freeze_param_types!
        param_types.freeze
        @param_types_frozen = true
      end

      def param_types_frozen?
        @param_types_frozen ||= false
      end

      # Drop the registry back to the built-ins and unfreeze it. For tests that
      # register a temporary type; never called in production.
      def reset_param_types!
        @param_types = Phlex::Reactive::ParamSchema.built_in_types.dup
        @param_types_frozen = false
      end

      # Emit an `<event>.phlex_reactive` ActiveSupport::Notifications event around
      # a block, yielding the mutable payload so a rescue can finalize the outcome
      # (issue #107). ASN.instrument is cheap when nothing is subscribed (the hot
      # paths depend on this — proven by the render bench), so this wraps the
      # render/broadcast/action paths unconditionally. The payload must carry
      # NAMES/outcome/sizes ONLY — never token/params/state.
      def instrument(event, payload = {}, &)
        ::ActiveSupport::Notifications.instrument("#{event}.#{INSTRUMENTATION_NAMESPACE}", payload, &)
      end

      # Register a COMPONENT-AWARE around_action wrapper (issue #112). The block
      # is folded into the endpoint BETWEEN with_connection_id and the action's
      # transaction — so it sees the resolved component instance, the declared
      # action name, and the coerced params (an ActionContext), and a rejection
      # NEVER opens a transaction. This is the seam for audit logging,
      # component-aware rate limiting, and assertions; the base controller
      # (base_controller_name) remains the seam for HTTP-layer concerns (auth,
      # CSRF, coarse per-IP rate limiting) that don't need the resolved action.
      #
      #   Phlex::Reactive.around_action do |ctx, &action|
      #     RateLimiter.check!(ctx.request.remote_ip, ctx.action_name) # raise -> 403
      #     result = action.call
      #     AuditLog.record!(actor: Current.user, action: ctx.action_name)
      #     result   # <- REQUIRED: return the continuation's value
      #   end
      #
      # CONTRACT — each wrapper MUST return `action.call`'s value. The endpoint
      # type-checks the action's return for a Phlex::Reactive::Response; a wrapper
      # that returns its logger's result instead silently downgrades every reply
      # to the implicit self-replace. Wrappers nest in registration order with the
      # LAST-registered outermost. Register in an initializer.
      def around_action(&block)
        raise ::ArgumentError, "Phlex::Reactive.around_action requires a block" unless block

        around_actions << block
      end

      # The registered around_action wrappers, oldest first. The endpoint folds
      # them so the last-registered runs outermost; an empty stack is the default
      # hot path (the controller short-circuits with `return yield`).
      def around_actions
        @around_actions ||= []
      end

      # Drop all registered around_action wrappers. For test isolation (the
      # shipped hook — specs registering a temporary wrapper reset around every
      # example); never called in production.
      def reset_around_actions!
        @around_actions = []
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

      # --- Deferred reply segments (issue #165) --------------------------

      # Lifetime (seconds) of a defer token. It only needs to cover the
      # reply→fetch gap (or reply→job→SSE on the push lane), so it stays short:
      # a leaked defer token is a render oracle for exactly one component
      # identity until this expires. nil resets to the default.
      attr_writer :defer_token_ttl

      def defer_token_ttl
        @defer_token_ttl ||= 120
      end

      # The path the defer endpoint is mounted at (the pull lane's target).
      # Default "/reactive/defer"; set before boot if it collides.
      attr_writer :defer_path

      def defer_path
        @defer_path ||= "/reactive/defer"
      end

      # How deferred segments reach the actor: :auto (push iff capable, else
      # pull), :fetch (always pull), :stream (push; degrades to pull with a
      # warning when the capability is absent). Validated at assignment — a
      # typo'd transport must fail at the initializer, not silently at reply
      # time. nil resets to the default.
      def defer_transport
        @defer_transport ||= :auto
      end

      def defer_transport=(value)
        value = value&.to_sym
        unless value.nil? || DEFER_TRANSPORTS.include?(value)
          raise ::ArgumentError,
            "Phlex::Reactive.defer_transport must be one of #{DEFER_TRANSPORTS.map(&:inspect).join(", ")} " \
            "(got #{value.inspect})"
        end

        @defer_transport = value
      end

      # The ActiveJob queue the push lane's DeferredRenderJob runs on. Default
      # "default"; point it at a fast queue in production — a deferred segment
      # is a UX-latency render, and letting it starve behind heavy jobs defeats
      # the point. nil resets to the default.
      attr_writer :defer_job_queue

      def defer_job_queue
        @defer_job_queue ||= "default"
      end

      # Signs a defer payload (issue #165): same shape + version stamp as the
      # identity token, but purpose-scoped to DEFER_PURPOSE and expiring after
      # defer_token_ttl. verify/verify_defer are therefore mutually exclusive
      # by construction — see the DEFER_PURPOSE comment.
      def sign_defer(payload)
        verifier.generate(
          payload.merge("v" => TOKEN_VERSION),
          purpose: DEFER_PURPOSE, expires_in: defer_token_ttl
        )
      end

      # Returns the verified, version-upgraded defer payload, or nil when the
      # token is tampered, expired, carries the wrong purpose (an action token),
      # or a version this code doesn't understand — all fail closed through the
      # endpoint's InvalidToken → 400 path.
      def verify_defer(token)
        payload = verifier.verified(token, purpose: DEFER_PURPOSE)
        payload && upgrade_token(payload)
      end

      # --- pgbus capability gates (issue #165) ---------------------------
      # Runtime capability detection, never `defined?(Pgbus)` alone or a
      # version string (the core optionality invariant): pgbus < 0.9.2 also
      # defines ::Pgbus, so the Streams gate probes the ACTUAL keyword.

      # Necessary but NOT sufficient — the Streams entrypoint exists.
      def pgbus?
        return false unless defined?(::Pgbus)

        ::Pgbus.respond_to?(:stream)
      end

      # The reactive-Streams capability: Stream#broadcast accepts :exclude
      # (the pgbus >= 0.9.2 shape). This is the gate that prevents
      # `ArgumentError: unknown keyword :exclude` on an old pgbus.
      def pgbus_streams?
        return false unless pgbus?
        return false unless defined?(::Pgbus::Streams::Stream)

        ::Pgbus::Streams::Stream.instance_method(:broadcast)
          .parameters.any? { |_type, name| name == :exclude }
      rescue ::NameError
        false
      end

      # Everything the defer PUSH lane needs at runtime: streams-capable pgbus,
      # server-side signed-src minting (SignedName.sign — the element's src is
      # built off-request), and ActiveJob to run the render off the request
      # thread. Anything missing → the pull lane (which is always available).
      def defer_push_capable?
        return false unless pgbus_streams?
        return false unless defined?(::Pgbus::Streams::SignedName) &&
                            ::Pgbus::Streams::SignedName.respond_to?(:sign)

        defined?(::ActiveJob::Base) ? true : false
      end

      # DOM id of the host-app container a Response#flash appends into.
      # Default "flash"; override to match your layout's flash region.
      def flash_target
        @flash_target ||= "flash"
      end

      attr_writer :flash_target

      # A user-visible flash rendered on every endpoint rescue path (issue #100).
      # Default nil = today's behavior (a bare head, or the verbose_errors
      # plain-text diagnostic). Set a lambda ->(kind) { "message" } (kind is
      # :tampered/:unknown_class/:not_reactive_class/:forbidden/:not_found) and
      # the ActionsController ALSO renders a turbo-stream flash into flash_target
      # — at the SAME status it returns today (statuses never change). Composes
      # with verbose_errors: the turbo-stream flash wins the response body, the
      # diagnostic still goes to the log.
      attr_accessor :error_flash

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
      # to build standalone streams not tied to a specific component's id — a
      # Response flash append, a reactive_collection row removal, a count
      # companion update, an also_update companion. Cached PER THREAD alongside
      # the context it's bound to (see off_request_view_context for why
      # per-thread). Renamed from flash_builder (issue #113): the builder does
      # far more than flashes, so the name misled. flash_builder stays a
      # permanent alias below so the engine's to_prepare and app code keep working.
      def stream_builder
        off_request_view_context_cache[:builder]
      end

      # The off-request view context for the current thread, built once and
      # reused for both the stream builder and standalone component renders.
      # Cached PER THREAD, not per process: an ActionView context carries mutable
      # output_buffer/view_flow state (render_in's capture swaps it), so sharing
      # one instance across threads can interleave content on a threaded server.
      # Rebuilt when the renderer object changes or the generation is bumped
      # (reset_stream_builder! / Rails code reload), so a reloaded controller is
      # never served stale.
      def off_request_view_context
        off_request_view_context_cache[:view_context]
      end

      # Invalidate the per-thread context + builder for ALL threads by bumping
      # the generation; each thread rebuilds lazily on next use. Registered on
      # Rails' reloader by the engine; also used by specs. Thread-safe (an
      # integer bump, no shared structure to tear down). Renamed from
      # reset_flash_builder! (issue #113); the old name stays a permanent alias
      # below so the engine's to_prepare hook keeps working.
      def reset_stream_builder!
        @off_request_view_context_generation = off_request_view_context_generation + 1
      end

      # Permanent aliases for the pre-#113 names. Kept forever (no deprecation)
      # so the engine's to_prepare hook and any app code calling the old names
      # keep working unchanged.
      alias flash_builder stream_builder
      alias reset_flash_builder! reset_stream_builder!

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

      # Returns the verified, version-upgraded payload hash, or nil if the token
      # is invalid (bad signature/purpose) OR carries a version this code doesn't
      # understand. The single verify choke point (issue #111): after the
      # signature check we run upgrade_token so an older-shape payload is migrated
      # to the current shape before from_identity ever sees it.
      def verify(token)
        payload = verifier.verified(token, purpose: IDENTITY_PURPOSE)
        payload && upgrade_token(payload)
      end

      # Signs a payload hash into an identity token, stamping the current
      # TOKEN_VERSION (issue #111). The "v" key is the ONLY thing added — a
      # from_identity that ignores unknown keys is unaffected.
      def sign(payload)
        verifier.generate(payload.merge("v" => TOKEN_VERSION), purpose: IDENTITY_PURPOSE)
      end

      # Migrate a verified payload from whatever version it was signed at up to
      # TOKEN_VERSION (issue #111). Runs the registered upgraders oldest → current,
      # then stamps the payload to the current version. Contract:
      #   * no "v"  → version 0 (the shape from before versioning existed). With no
      #     v0 upgrader registered this is a pure passthrough — introducing
      #     versioning invalidates NOTHING already in flight.
      #   * v == current → returned as-is (the hot path — one integer compare).
      #   * v  > current → nil. A rolled-back deploy verifying a token minted by
      #     NEWER code must not guess the newer shape; returning nil fails closed
      #     through the endpoint's existing `|| raise(InvalidToken)` → 400.
      def upgrade_token(payload)
        version = payload.fetch("v", 0)
        # "v" is inside the signed blob, so only our own key could produce a
        # malformed one — but fail closed rather than 500 on the comparison
        # (String vs Integer) or silently treat a negative "v" as legacy.
        return nil unless version.is_a?(::Integer) && version >= 0
        return payload if version == TOKEN_VERSION
        return nil if version > TOKEN_VERSION

        upgrade_from(payload, version)
      end

      # Register an upgrader that rewrites a payload signed at `from_version` into
      # the shape of `from_version + 1` (issue #111). Register in load order at
      # boot when you bump TOKEN_VERSION; the block receives the payload hash and
      # returns the migrated hash (the "v" stamp is applied by upgrade_token, so
      # the block only reshapes the data). Example, for a future count → n rename:
      #
      #   Phlex::Reactive.register_token_upgrader(0) do |payload|
      #     payload.merge("s" => { "n" => payload.dig("s", "count") })
      #   end
      def register_token_upgrader(from_version, &block)
        raise ::ArgumentError, "register_token_upgrader requires a block" unless block

        token_upgraders[Integer(from_version)] = block
      end

      # from_version => callable(payload) -> migrated payload. Sparse: an entry
      # exists only for a version that actually changed shape.
      def token_upgraders
        @token_upgraders ||= {}
      end

      # Drop all registered upgraders. For tests that register a temporary one.
      def reset_token_upgraders!
        @token_upgraders = {}
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

      # Walk the upgrader chain from `version` up to TOKEN_VERSION, applying each
      # registered upgrader in turn (issue #111). A gap in the chain (a version
      # bumped with no shape change, so no upgrader registered) is a no-op step —
      # the payload passes through unchanged to the next version. Only stamp the
      # current "v" if an upgrader ACTUALLY reshaped the payload: a versionless
      # (v0) token with no upgraders registered — today's case — is returned
      # byte-identical, so introducing versioning invalidates nothing in flight.
      # Runs only for a genuinely old token (the v == current hot path already
      # returned in upgrade_token), so this is off the render path.
      def upgrade_from(payload, version)
        upgraded = false
        version.upto(TOKEN_VERSION - 1) do
          upgrader = token_upgraders[it]
          next unless upgrader

          payload = upgrader.call(payload)
          upgraded = true
        end
        upgraded ? payload.merge("v" => TOKEN_VERSION) : payload
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
# js.rb defines JS and component/dsl.rb defines Component::DSL (acronyms), not
# the default-inflected `Js`/`Dsl`.
loader.inflector.inflect("js" => "JS", "dsl" => "DSL")
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
# The RSpec matchers file (issue #110) defines RSpec::Matchers, not a
# Phlex::Reactive::TestHelpers::Matchers constant, so it doesn't follow
# Zeitwerk's naming — test_helpers.rb requires it explicitly (only when RSpec is
# present), and the loader must ignore it.
loader.ignore("#{lib}/phlex/reactive/test_helpers/matchers.rb")
# The engine is required explicitly below (only when Rails is present) and must
# not be eager-loaded before that.
loader.do_not_eager_load("#{__dir__}/reactive/engine.rb")
# The defer push-lane job subclasses ActiveJob::Base, which is NOT a gem
# dependency — eager-loading it in an app without ActiveJob would raise at
# boot. The constant autoloads on first reference, which only happens behind
# Phlex::Reactive.defer_push_capable? (that gate requires ActiveJob::Base).
loader.do_not_eager_load("#{__dir__}/reactive/deferred_render_job.rb")
loader.setup

require "phlex/reactive/engine" if defined?(Rails::Engine)
