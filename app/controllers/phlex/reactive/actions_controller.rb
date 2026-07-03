# frozen_string_literal: true

module Phlex
  module Reactive
    # The single endpoint behind every reactive component. The generic
    # `reactive` Stimulus controller POSTs here with a signed identity token,
    # an action name, and params. We verify the token, rebuild the component
    # (re-finding the record from the DB for record-backed components), run the
    # whitelisted action, and return an auto-targeted Turbo Stream the client
    # morphs in.
    #
    # Customizing in your app:
    #   * Authentication — by default this inherits from
    #     Phlex::Reactive.base_controller (ActionController::Base). Set it to
    #     your ApplicationController to get current_user/Current/CSRF, but make
    #     sure the action path isn't force-redirected for logged-out users if
    #     you have public reactive components.
    #   * Authorization — DO IT IN THE COMPONENT ACTION. The token proves the
    #     identity is ours, not that this user may act. Raise from the action
    #     (e.g. authorize!), and configure Phlex::Reactive.authorization_errors
    #     so it's rendered as 403 here.
    class ActionsController < Phlex::Reactive.base_controller
      # Our JSON body uses keys that collide with Rails' reserved routing
      # params (action/controller) and would be wrapped by wrap_parameters.
      # Disable wrapping so the body lands flat; the action name travels as
      # `act` (not `action`, which is reserved and resolves to "create").
      wrap_parameters false if respond_to?(:wrap_parameters)

      def create
        # ONE action.phlex_reactive event per request (issue #107). The event
        # payload carries the component/action NAMES + outcome ONLY (never the
        # token, params, or state); we fill it as those become known and set
        # :outcome on every exit path — the success tail and each rescue. The
        # rescue bodies are unchanged (verbose diagnostics + reactive_error per
        # #82/#87); we only ADD the outcome finalizer. `action` is safe to read
        # up front (it comes from the request, not the verified token).
        event = { component: nil, action: reactive_action_name.to_s, outcome: nil }
        Phlex::Reactive.instrument("action", event) do
          create_action(event)
        end
      end

      private

      # The action body, run inside the instrument block so its payload (`event`)
      # can be finalized on every exit path. Kept separate so `create` stays a
      # thin instrument wrapper.
      def create_action(event)
        payload = verified_payload
        component_class = resolve_component(payload["c"])
        event[:component] = component_class.name
        action_def = component_class.reactive_action(reactive_action_name)

        # default-deny
        unless action_def
          event[:outcome] = :denied_undeclared
          return reactive_error(:forbidden, undeclared_action_message(component_class), kind: :forbidden)
        end

        component = component_class.from_identity(payload)
        coerced = coerce_params(action_def.params, component_class:, action_name: action_def.name)

        result = run_action(component, action_def, coerced)

        event[:outcome] = :ok
        render turbo_stream: response_streams(result, component)
      rescue Phlex::Reactive::InvalidToken => e
        # The component name here came from an UNVERIFIED token — do NOT report it
        # as trusted. Leave event[:component] nil.
        event[:outcome] = :invalid_token
        reactive_error(:bad_request, e.message, kind: e.diagnostic || :tampered)
      rescue ActiveRecord::RecordNotFound
        event[:outcome] = :not_found
        reactive_error(:not_found, record_not_found_message(payload), kind: :not_found)
      rescue *authorization_errors => e
        event[:outcome] = :unauthorized
        reactive_error(:forbidden, authorization_error_message(e, component_class, action_def), kind: :forbidden)
      end

      # Reply to an endpoint failure. The status NEVER changes with any flag —
      # only the body. Precedence for the body (issue #100):
      #   1. error_flash set → a turbo-stream flash the user actually SEES (the
      #      client renders non-OK turbo-stream bodies). It wins over the verbose
      #      diagnostic (both can't be the body); the diagnostic still logs below.
      #   2. else verbose_errors → the plain-text diagnostic (client console.errors it).
      #   3. else a bare head.
      # The warn log fires in EVERY environment first, so a misbehaving client is
      # debuggable from the server log alone regardless of which body path runs.
      def reactive_error(status, message, kind: nil)
        ::Rails.logger&.warn("[phlex-reactive] #{message}") if defined?(::Rails) && ::Rails.respond_to?(:logger)

        flash = error_flash_stream(kind)
        if flash
          render turbo_stream: flash, status: status
        elsif Phlex::Reactive.verbose_errors
          render plain: message, status: status
        else
          head status
        end
      end

      # Build the error flash turbo-stream when Phlex::Reactive.error_flash is
      # configured, else nil (the non-flash body paths run). Degrades gracefully:
      # a lambda that raises returns nil so the endpoint falls back to the bare/
      # diagnostic body and NEVER turns one failure into a 500.
      def error_flash_stream(kind)
        callable = Phlex::Reactive.error_flash
        return unless callable

        message = callable.call(kind)
        Phlex::Reactive::Response.flash_stream(:error, message, target: Phlex::Reactive.flash_target)
      rescue => e # rubocop:disable Style/RescueStandardError
        ::Rails.logger&.warn("[phlex-reactive] error_flash raised: #{e.message}") if defined?(::Rails) &&
                                                                                     ::Rails.respond_to?(:logger)
        nil
      end

      def undeclared_action_message(component_class)
        declared = component_class.reactive_actions.keys.join(", ")
        "action :#{reactive_action_name} is not declared on #{component_class.name} — " \
          "declared actions: #{declared}"
      end

      def record_not_found_message(payload)
        gid = payload.is_a?(Hash) && payload["gid"]
        return "record not found" unless gid

        "record #{gid} not found — deleted while a page still showed it?"
      end

      def authorization_error_message(error, component_class, action_def)
        where = [component_class&.name, action_def&.name].compact.join("#")
        "#{error.class.name} raised in #{where} — the signature proves identity, not permission; " \
          "authorize in the action"
      end

      # Run the action inside a transaction so transactional broadcasts (pgbus
      # broadcasts_to ... durable:) defer to after_commit and never fire for a
      # rolled-back change. Override to add per-request instrumentation.
      #
      # The actor's SSE connection id (sent as X-Pgbus-Connection) is exposed
      # for the duration of the action via Phlex::Reactive.current_connection_id,
      # so a broadcast in the action can pass exclude: reactive_connection_id
      # and skip the actor's own echo.
      def run_action(component, action_def, coerced)
        Phlex::Reactive.with_connection_id(request.headers["X-Pgbus-Connection"]) do
          transaction_wrapper do
            if coerced.any?
              component.public_send(action_def.name, **coerced)
            else
              component.public_send(action_def.name)
            end
          end
        end
      end

      # Turn the action's return value into the turbo-stream(s) to render for
      # the actor. A Phlex::Reactive::Response is honored explicitly; any other
      # value (the legacy contract — return value ignored) falls back to the
      # implicit single replace, so existing actions are unaffected.
      def response_streams(result, component)
        return [component.to_stream_replace] unless result.is_a?(Phlex::Reactive::Response)
        return [redirect_stream(result.redirect_url)] if result.redirect?

        streams = result.streams

        # Partial update (Response.streams / reply.streams, issue #30): the action
        # re-rendered only PART of the component and opted out of the full-self
        # replace. Append a tiny token-only stream so the signed token still rolls
        # forward WITHOUT re-rendering (and clobbering) the live inputs. Skip it
        # only if the caller already supplied THIS component's token (idempotent) —
        # the dedupe is scoped to the actor's own target, NOT a global substring,
        # so a partial reply that legitimately includes another reactive
        # component's stream (which carries its OWN token) still refreshes ours.
        if result.refresh_token? && !carries_token_for?(streams, result.token_component)
          return [*streams, result.token_component.to_stream_token]
        end

        # Guarantee the component's signed identity token is refreshed unless the
        # Response opted out (remove/redirect navigate away — handled above). The
        # client reads the next token from the response body (#extractToken), so
        # the real invariant is "a fresh data-reactive-token-value is present",
        # NOT "some stream targets self". Checking the token directly is correct
        # for replace AND update of self (both re-render the root via
        # render_component, carrying the token), and still adds the fallback
        # replace when a hand-built `with(...)` stream omits it. Idempotent: a
        # Response.replace(self)/update(self) already carries the token, so we
        # don't double the self-render.
        if result.render_self? && streams.none? { it.include?("data-reactive-token-value") }
          streams = [component.to_stream_replace, *streams]
        end
        streams
      end

      # Actions that RE-RENDER the component's own root (so the root's fresh
      # data-reactive-token-value rolls the signed token forward). `append`/
      # `prepend` are deliberately excluded: they insert CHILDREN into the
      # component, and a reactive child carries its OWN token — that child token is
      # not the component's (issue #44). reactive:token is our inert token-only
      # refresh; replace/update re-render the root.
      SELF_RENDER_ACTIONS = %w[replace update reactive:token].freeze
      private_constant :SELF_RENDER_ACTIONS

      # True when one of `streams` already carries a fresh token by RE-RENDERING
      # this component itself — i.e. the caller hand-built the actor's own
      # token-bearing stream, so appending to_stream_token would double it.
      #
      # The match requires BOTH (a) the stream's action re-renders the component's
      # ROOT (replace/update/reactive:token — never append/prepend, which insert
      # children) AND (b) it targets the component's id AND (c) it actually carries
      # a token. This is stricter than a same-string substring check on purpose:
      #   * A sibling component's replace targets a DIFFERENT id → (b) fails, so we
      #     still refresh ours (issue #30).
      #   * A reactive child row appended/prepended INTO the component carries its
      #     own token at the component's target, but the action is append/prepend →
      #     (a) fails, so we still refresh the CONTAINER's token (issue #44). Before
      #     this, the child's token at the container target suppressed the
      #     container's refresh and the list was add-once-only.
      def carries_token_for?(streams, component)
        target = %(target="#{ERB::Util.html_escape(component.id)}")
        streams.any? do
          it.include?("data-reactive-token-value") &&
            it.include?(target) &&
            self_render_stream_for?(it, target)
        end
      end

      # Does this turbo-stream's OPENING tag re-render `target` itself? Matches a
      # `<turbo-stream action="<self-render>" ... target="<id>">` opening tag — the
      # action and target on the SAME tag — so a child row's token embedded in an
      # append/prepend `<template>` can never count as the container's own refresh.
      def self_render_stream_for?(stream, target)
        open_tag = stream[/<turbo-stream\b[^>]*>/]
        return false unless open_tag&.include?(target)

        action = open_tag[/\baction="([^"]+)"/, 1]
        SELF_RENDER_ACTIONS.include?(action)
      end

      # A 200 turbo-stream carrying a namespaced custom action the client turns
      # into Turbo.visit — NOT an HTTP 3xx, which the client hard-bails on
      # (response.redirected). The matching client handler is registered in
      # reactive_controller.js.
      def redirect_stream(url)
        %(<turbo-stream action="reactive:visit" data-url="#{ERB::Util.html_escape(url)}"></turbo-stream>)
      end

      def transaction_wrapper(&)
        if defined?(::ActiveRecord::Base)
          ::ActiveRecord::Base.transaction(&)
        else
          yield
        end
      end

      def verified_payload
        token = params.require(:token)
        Phlex::Reactive.verify(token) || raise(Phlex::Reactive::InvalidToken.new(
          "token signature invalid — stale token from before a deploy? secret_key_base mismatch? " \
          "a reply.with(...) stream that skipped the token refresh?",
          diagnostic: :tampered
        ))
      end

      # NB: must NOT be named `action_name` — that's reserved by
      # ActionController dispatch and overriding it recurses fatally.
      def reactive_action_name
        params.require(:act).to_sym
      end

      # Coerce client params against the action's declared schema. Anything not
      # in the schema is dropped — no raw mass assignment reaches the component.
      # The top-level params arrive as an ActionController::Parameters; coerce
      # them against the action's hash schema (same recursion as nested hashes).
      #
      # With verbose_errors on, every dropped key is collected (full bracketed
      # path + reason) and warn-logged once per action. With the flag off the
      # collector is nil and every diagnostic branch below early-returns —
      # zero extra work on the production path.
      def coerce_params(schema, component_class: nil, action_name: nil)
        dropped = Phlex::Reactive.verbose_errors ? [] : nil

        # A schema-less action drops EVERYTHING the client posted. Still surface
        # that in verbose mode — forgetting the `params:` declaration entirely is
        # the loudest version of the silent drop.
        if schema.blank?
          log_schemaless_drops(dropped, component_class, action_name) if dropped
          return {}
        end

        coerced = coerce_hash(params.fetch(:params, {}), schema, dropped, nil)
        log_dropped_params(dropped, schema, component_class, action_name)
        coerced
      end

      # Sentinel: a declared key whose value can't be coerced to its type is
      # DROPPED (not assigned), so the method's keyword default applies — exactly
      # as if the client had omitted the key. Distinct from a coerced nil/[].
      DROP = Object.new
      private_constant :DROP

      # Coerce a value against a declared type. A type is one of:
      #   * a scalar symbol            (:string/:integer/:float/:boolean)
      #   * :file                      — a multipart upload (issue #34)
      #   * a Hash schema              ({ id: :integer, ... })   — nested object
      #   * a one-element Array        ([:integer] / [{ ... }])  — array of that
      # Arrays accept both a real JSON array and a Rails-style index hash
      # ({ "0" => ..., "1" => ... }), so a fields_for collection works either way.
      def coerce(value, type, dropped = nil, path = nil)
        case type
        when Array
          coerce_array(value, type.first, dropped, path)
        when Hash
          coerce_hash(value, type, dropped, path)
        when :file
          coerce_file(value)
        else
          coerce_scalar(value, type)
        end
      end

      # An uploaded file (issue #34) passes through UNTOUCHED — never .to_s'd,
      # which would corrupt it into a string the action can't attach. Anything
      # that isn't an uploaded file (a forged/malformed scalar, an empty input)
      # returns DROP, so the method's keyword default applies — consistent with
      # the #16 rule that a value that can't be coerced to its type is dropped,
      # not fabricated. Duck-types on UploadedFile's interface (original_filename
      # + a readable IO) rather than naming a class, so a Rack::Test upload, an
      # ActionDispatch upload, and a Falcon multipart body all qualify.
      def coerce_file(value)
        uploaded_file?(value) ? value : DROP
      end

      def uploaded_file?(value)
        value.respond_to?(:original_filename) && value.respond_to?(:read)
      end

      # A real array (or Rails index hash) coerces element-wise. A malformed
      # present-but-non-array value returns DROP rather than [] — coercing a stray
      # scalar to an empty array would let a bad payload read as an explicit
      # "clear everything" on update!(declared_array:).
      #
      # An ELEMENT that coerces to DROP (e.g. a non-file in a [:file] array, a
      # forged/mixed payload) is rejected from the result — the same rule
      # coerce_hash applies to a dropped value, so the internal DROP sentinel
      # never leaks into the action. A genuinely empty input array stays [] (an
      # explicit empty collection), but an array whose every element drops
      # returns DROP, so the keyword default applies rather than handing the
      # action a surprise [].
      def coerce_array(value, element_type, dropped = nil, path = nil)
        values = array_values(value)
        return DROP if values.nil?
        return [] if values.empty?

        coerced =
          if dropped
            # Record each element that coerces to DROP (a forged non-file in a
            # [:file] array) under its bracketed index — reject! below removes
            # it from the result, so this is its only trace.
            values.map.with_index do |element, i|
              element_path = "#{path}[#{i}]"
              result = coerce(element, element_type, dropped, element_path)
              dropped << [element_path, :uncoercible] if result.equal?(DROP)
              result
            end
          else
            values.map { coerce(it, element_type) }
          end
        coerced.reject! { it.equal?(DROP) }
        coerced.empty? ? DROP : coerced
      end

      # Keep declared keys only (drop undeclared — no mass assignment), recursing
      # for nested hash/array element types. Symbolizes keys to splat as kwargs.
      # A key whose value coerces to DROP is skipped (keyword default applies).
      # `dropped`/`path` are the verbose_errors diagnostics collector — nil (and
      # cost-free) unless the flag is on.
      def coerce_hash(value, schema, dropped = nil, path = nil)
        hash = to_param_hash(value)
        collect_undeclared(dropped, hash, schema, path) if dropped
        schema.each_with_object({}) do |(key, type), out|
          key_name = key.to_s
          next unless hash.key?(key_name)

          key_path = dropped && join_path(path, key_name)
          coerced = coerce(hash[key_name], type, dropped, key_path)
          if coerced.equal?(DROP)
            dropped << [key_path, :uncoercible] if dropped
            next
          end

          out[key.to_sym] = coerced
        end
      end

      # ---- verbose_errors dropped-param diagnostics ----------------------
      # Everything below runs ONLY when the collector exists (flag on); the
      # production path never reaches these methods.

      def join_path(path, key)
        path ? "#{path}[#{key}]" : key
      end

      # Record every input key this schema level doesn't declare. A hash value
      # expands to its leaf paths so the log shows the full bracketed name the
      # client posted (invoice[date], not just invoice).
      def collect_undeclared(dropped, hash, schema, path)
        declared = schema.keys.map(&:to_s)
        hash.each do |key, value|
          next if declared.include?(key)

          record_undeclared(dropped, join_path(path, key), value)
        end
      end

      def record_undeclared(dropped, path, value)
        if value.is_a?(Hash) && value.any?
          value.each { |key, child| record_undeclared(dropped, "#{path}[#{key}]", child) }
        else
          dropped << [path, :undeclared]
        end
      end

      # ONE warn line per action naming every dropped param with its reason —
      # plus, for the #16/#21 confusion, a hint when a dropped name looks like
      # the flat/bracketed twin of a declared key.
      def log_dropped_params(dropped, schema, component_class, action_name)
        return if dropped.nil? || dropped.empty?
        return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

        entries = dropped.map { |path, reason| "#{path} (#{dropped_reason(path, reason, schema)})" }
        where = [component_class, action_name].compact.join("#")
        where = "#{where} " unless where.empty?
        ::Rails.logger.warn("[phlex-reactive] #{where}dropped params: #{entries.join(", ")}")
      end

      def dropped_reason(path, reason, schema)
        return reason.to_s unless reason == :undeclared
        return "undeclared — the action declares no params" if schema.empty?

        hint = shape_hint(path, schema)
        hint ? "undeclared — #{hint}" : "undeclared"
      end

      # Collect + log for an action with NO declared schema: every posted key is
      # undeclared by definition (CodeRabbit review on PR #87). Runs only when
      # the verbose collector exists.
      def log_schemaless_drops(dropped, component_class, action_name)
        collect_undeclared(dropped, to_param_hash(params.fetch(:params, {})), {}, nil)
        log_dropped_params(dropped, {}, component_class, action_name)
      end

      # Fires only when a dropped segment matches a DECLARED key at a different
      # nesting level — a bracketed name whose leaf the schema declares flat, or
      # a flat name the schema declares one level down. Deliberately simple: it
      # searches one nesting level (hash / array-of-hash), no deeper.
      def shape_hint(path, schema)
        segments = bracket_path(path)
        if segments.length > 1
          leaf = segments.last
          return unless schema.key?(leaf.to_sym)

          "schema declares :#{leaf} at top level; nested schemas look like " \
            "{ #{segments.first}: { #{leaf}: :string } }"
        else
          parent = nested_declaration_of(segments.first, schema)
          return unless parent

          "schema declares :#{segments.first} nested under :#{parent}; " \
            "post it as #{parent}[#{segments.first}]"
        end
      end

      # The first schema key whose nested hash (or array-of-hash element
      # schema) declares `name` one level down.
      def nested_declaration_of(name, schema)
        schema.find do |_key, type|
          inner = type.is_a?(Array) ? type.first : type
          inner.is_a?(Hash) && inner.key?(name.to_sym)
        end&.first
      end

      # ---- end verbose_errors diagnostics --------------------------------

      def coerce_scalar(value, type)
        case type
        when :integer then value.to_i
        when :float then value.to_f
        when :boolean then ActiveModel::Type::Boolean.new.cast(value)
        else value.to_s
        end
      end

      # Normalize an array param: a real array passes through; a Rails index hash
      # ({ "0" => ..., "1" => ... }) becomes its values in index order. Anything
      # else (a stray scalar, nil) is malformed → nil, so the caller drops the
      # param rather than fabricating an empty array.
      def array_values(value)
        return value.to_a if value.is_a?(Array)

        return unless value.respond_to?(:to_unsafe_h) || value.is_a?(Hash)

        to_param_hash(value).sort_by { |k, _| k.to_i }.map(&:last)
      end

      # Unwrap ActionController::Parameters (or a plain Hash) to a string-keyed
      # Hash so coercion can index it uniformly, then expand bracket notation so
      # a model-scoped Rails form's flat keys nest (issue #21).
      def to_param_hash(value)
        flat =
          if value.respond_to?(:to_unsafe_h)
            value.to_unsafe_h.stringify_keys
          elsif value.is_a?(Hash)
            value.stringify_keys
          else
            return {}
          end

        expand_bracket_keys(flat)
      end

      # The client's #collectFields keeps a form input's name verbatim, so a
      # Rails Form(model: @invoice) posts FLAT bracketed keys like
      # "invoice[date]". Coercion does exact-key matching, so without this a
      # nested schema (params: { invoice: { date: … } }) never finds "invoice"
      # and drops everything. Expand "invoice[date]" => "2026-01-02" into
      # { "invoice" => { "date" => "2026-01-02" } } — and "items[0][qty]" into
      # the Rails index-hash form coerce_array already understands — deep-merging
      # so sibling keys (invoice[date], invoice[status]) coalesce. Keys WITHOUT
      # brackets and already-nested values pass through untouched, so a
      # pre-nested object (issue #16) and plain scalars still work. Value types
      # (a checkbox boolean, an explicit array) are preserved verbatim — unlike a
      # round-trip through parse_nested_query, which only handles strings.
      def expand_bracket_keys(flat)
        flat.each_with_object({}) do |(key, value), out|
          deep_assign(out, bracket_path(key), value)
        end
      end

      # Matches each bracket segment in "items_attributes][0][qty]" — the part
      # after the first "[". Hoisted to a frozen constant so coercing a bracketed
      # key doesn't recompile the pattern per key on every request.
      BRACKET_SEGMENT = /[^\[\]]+/
      private_constant :BRACKET_SEGMENT

      # "invoice[items_attributes][0][qty]" => ["invoice", "items_attributes",
      # "0", "qty"]. A key with no brackets is a single-element path.
      def bracket_path(key)
        return [key] unless key.include?("[")

        head, rest = key.split("[", 2)
        [head, *rest.scan(BRACKET_SEGMENT)]
      end

      # Walk/create nested hashes along `path`, then merge `value` at the leaf so
      # a bracket key and a sibling pre-nested object coalesce regardless of which
      # arrives first ({ "invoice[date]" => …, invoice: { status: … } } keeps
      # both). #merge_value deep-merges hash/hash collisions and otherwise lets
      # the later value win (a bracket key colliding with a flat scalar).
      def deep_assign(hash, path, value)
        *parents, leaf = path
        node = parents.reduce(hash) do |acc, segment|
          acc[segment] = {} unless acc[segment].is_a?(Hash)
          acc[segment]
        end
        node[leaf] = merge_value(node[leaf], value)
      end

      # Combine an existing leaf value with a new one. Two hashes deep-merge (so
      # bracket-expanded fields and a pre-nested object for the same key both
      # survive); any other collision takes the new value.
      def merge_value(existing, value)
        return value unless existing.is_a?(Hash) && value.is_a?(Hash)

        existing.merge(value.stringify_keys) { |_k, old, new| merge_value(old, new) }
      end

      # Only components that opt into Reactive may be resolved. The signature
      # already gates this; defense in depth against constant injection. The
      # two failure causes carry distinct diagnostics: a name that doesn't
      # resolve at all vs a constant that resolved but isn't a reactive
      # component.
      def resolve_component(name)
        klass = name.to_s.safe_constantize
        unless klass
          raise Phlex::Reactive::InvalidToken.new(
            "token class #{name} does not resolve — component renamed/removed while a page was open?",
            diagnostic: :unknown_class
          )
        end
        unless klass.respond_to?(:reactive_action?) && klass.include?(Phlex::Reactive::Component)
          raise Phlex::Reactive::InvalidToken.new(
            "#{name} resolved but does not include Phlex::Reactive::Component",
            diagnostic: :not_reactive_class
          )
        end

        klass
      end

      def authorization_errors
        Phlex::Reactive.authorization_errors
      end
    end
  end
end
