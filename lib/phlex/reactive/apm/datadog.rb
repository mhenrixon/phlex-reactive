# frozen_string_literal: true

module Phlex
  module Reactive
    module APM
      # Datadog adapter (issue #207, dd-trace-rb). Activates only when
      # `::Datadog::Tracing` is loaded. Renames the ACTIVE span `Component#action`
      # + tags it, so the reactive action shows as its own resource in the trace;
      # marks the active span errored on an action-body crash. No-ops with no
      # active span (never opens one itself — that's the app's tracer's job).
      class Datadog < Adapter
        def self.available?
          return false unless defined?(::Datadog::Tracing)

          ::Datadog.respond_to?(:configuration)
        end

        def record_action(payload, _duration_ms)
          span = active_span
          return unless span

          name = transaction_name(payload)
          span.resource = name if name
          span.set_tag("reactive.component", payload[:component]) if payload[:component]
          span.set_tag("reactive.action", payload[:action]) if payload[:action]
          span.set_tag("reactive.outcome", payload[:outcome].to_s) if payload[:outcome]
        end

        def record_error(error, payload)
          span = active_span
          return unless span

          span.set_error(error)
          span.set_tag("reactive.component", payload[:component]) if payload[:component]
          span.set_tag("reactive.action", payload[:action]) if payload[:action]
        end

        private

        def active_span = ::Datadog::Tracing.active_span
      end
    end
  end
end
