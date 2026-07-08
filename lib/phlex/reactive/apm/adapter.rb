# frozen_string_literal: true

module Phlex
  module Reactive
    module APM
      # The adapter contract (issue #207). A custom APM integration need only be an
      # object responding to these two methods — it does NOT have to subclass this;
      # the class documents the interface and gives the built-in vendor adapters a
      # shared home for the small helpers they all use.
      #
      #   record_action(payload, duration_ms)
      #     payload is the name-only action/defer event payload
      #     ({ component:, action:, outcome: } — action:/nil for defer). Name the
      #     APM transaction and tag the outcome. Called on EVERY reactive action.
      #
      #   record_error(error, payload)
      #     error is the raised exception; payload is the same name-only hash. Report
      #     the exception to the tracker WITH component/action tags. Called only on a
      #     previously-uncaught action-body error (a 500), just before the re-raise.
      #
      # A built-in adapter also answers `.available?` (a runtime `defined?(SDK)`
      # probe) so the resolver can no-op when the SDK isn't loaded.
      class Adapter
        # The APM transaction name for a payload: "Component#action", or just the
        # component when there's no action (a defer event), or nil when there's no
        # trusted component (an invalid_token event carries none).
        def transaction_name(payload)
          component = payload[:component]
          return nil unless component

          action = payload[:action]
          action ? "#{component}##{action}" : component
        end

        # Present but not enforced — a bare Adapter is not a usable APM. The vendor
        # subclasses override all three.
        def self.available? = false
        def record_action(_payload, _duration_ms) = nil
        def record_error(_error, _payload) = nil
      end
    end
  end
end
