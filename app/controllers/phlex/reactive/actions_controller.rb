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
        payload = verified_payload
        component_class = resolve_component(payload["c"])
        action_def = component_class.reactive_action(reactive_action_name)

        return head(:forbidden) unless action_def # default-deny

        component = component_class.from_identity(payload)
        coerced = coerce_params(action_def.params)

        result = run_action(component, action_def, coerced)

        render turbo_stream: response_streams(result, component)
      rescue Phlex::Reactive::InvalidToken
        head :bad_request
      rescue ActiveRecord::RecordNotFound
        head :not_found
      rescue *authorization_errors
        head :forbidden
      end

      private

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
        if result.render_self? && streams.none? { |s| s.include?("data-reactive-token-value") }
          streams = [component.to_stream_replace, *streams]
        end
        streams
      end

      # True when one of `streams` already carries a fresh token TARGETING this
      # component — i.e. the caller hand-built the actor's own token-bearing
      # stream, so appending to_stream_token would double it. Scoped to the
      # component's target id (not a global substring) so a sibling component's
      # stream, which carries its OWN token for a DIFFERENT target, doesn't fool
      # us into skipping this component's refresh.
      def carries_token_for?(streams, component)
        target = %(target="#{ERB::Util.html_escape(component.id)}")
        streams.any? { |s| s.include?("data-reactive-token-value") && s.include?(target) }
      end

      # A 200 turbo-stream carrying a namespaced custom action the client turns
      # into Turbo.visit — NOT an HTTP 3xx, which the client hard-bails on
      # (response.redirected). The matching client handler is registered in
      # reactive_controller.js.
      def redirect_stream(url)
        %(<turbo-stream action="reactive:visit" data-url="#{ERB::Util.html_escape(url)}"></turbo-stream>)
      end

      def transaction_wrapper(&block)
        if defined?(::ActiveRecord::Base)
          ::ActiveRecord::Base.transaction(&block)
        else
          yield
        end
      end

      def verified_payload
        token = params.require(:token)
        Phlex::Reactive.verify(token) || raise(Phlex::Reactive::InvalidToken)
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
      def coerce_params(schema)
        return {} if schema.blank?

        coerce_hash(params.fetch(:params, {}), schema)
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
      def coerce(value, type)
        if type.is_a?(Array)
          coerce_array(value, type.first)
        elsif type.is_a?(Hash)
          coerce_hash(value, type)
        elsif type == :file
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
      def coerce_array(value, element_type)
        values = array_values(value)
        return DROP if values.nil?

        values.map { |element| coerce(element, element_type) }
      end

      # Keep declared keys only (drop undeclared — no mass assignment), recursing
      # for nested hash/array element types. Symbolizes keys to splat as kwargs.
      # A key whose value coerces to DROP is skipped (keyword default applies).
      def coerce_hash(value, schema)
        hash = to_param_hash(value)
        schema.each_with_object({}) do |(key, type), out|
          next unless hash.key?(key.to_s)

          coerced = coerce(hash[key.to_s], type)
          next if coerced.equal?(DROP)

          out[key.to_sym] = coerced
        end
      end

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

        if value.respond_to?(:to_unsafe_h) || value.is_a?(Hash)
          to_param_hash(value).sort_by { |k, _| k.to_i }.map(&:last)
        end
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
      # already gates this; defense in depth against constant injection.
      def resolve_component(name)
        klass = name.to_s.safe_constantize
        unless klass&.respond_to?(:reactive_action?) && klass.include?(Phlex::Reactive::Component)
          raise Phlex::Reactive::InvalidToken
        end

        klass
      end

      def authorization_errors
        Phlex::Reactive.authorization_errors
      end
    end
  end
end
