# frozen_string_literal: true

module Phlex
  module Reactive
    module APM
      # Sentry adapter (issue #207). Activates only when `::Sentry` is loaded AND
      # initialized. Sentry's chief value here is error reporting: an action-body
      # crash is captured WITH component/action tags. record_action names the
      # transaction on the current scope for the successful path.
      class Sentry < Adapter
        def self.available?
          return false unless defined?(::Sentry) && ::Sentry.respond_to?(:initialized?)

          ::Sentry.initialized?
        end

        def record_action(payload, _duration_ms)
          name = transaction_name(payload)
          return unless name

          ::Sentry.configure_scope { it.set_transaction_name(name) }
        end

        def record_error(error, payload)
          ::Sentry.capture_exception(error, tags: tags(payload))
        end

        private

        def tags(payload)
          {
            reactive_component: payload[:component],
            reactive_action: payload[:action],
            reactive_outcome: payload[:outcome]&.to_s
          }.compact
        end
      end
    end
  end
end
