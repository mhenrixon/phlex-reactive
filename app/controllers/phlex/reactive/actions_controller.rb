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

        run_action(component, action_def, coerced)

        render turbo_stream: component.to_stream_replace
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
      def run_action(component, action_def, coerced)
        transaction_wrapper do
          if coerced.any?
            component.public_send(action_def.name, **coerced)
          else
            component.public_send(action_def.name)
          end
        end
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
      def coerce_params(schema)
        return {} if schema.blank?

        raw = params.fetch(:params, {})
        schema.each_with_object({}) do |(key, type), out|
          next unless raw.key?(key.to_s)

          out[key.to_sym] = coerce(raw[key.to_s], type)
        end
      end

      def coerce(value, type)
        case type
        when :integer then value.to_i
        when :float   then value.to_f
        when :boolean then ActiveModel::Type::Boolean.new.cast(value)
        else value.to_s
        end
      end

      # Only components that opt into Reactive may be resolved. The signature
      # already gates this; defense in depth against constant injection.
      def resolve_component(name)
        klass = name.to_s.safe_constantize
        unless klass && klass.respond_to?(:reactive_action?) && klass.include?(Phlex::Reactive::Component)
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
