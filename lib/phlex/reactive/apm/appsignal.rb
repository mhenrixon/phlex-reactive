# frozen_string_literal: true

module Phlex
  module Reactive
    module APM
      # AppSignal adapter (issue #207). Activates only when `::Appsignal` is loaded
      # — never a gemspec dependency. Names the current transaction `Component#action`
      # (so reactive traffic stops rolling into one ActionsController#create blob) and
      # tags component/action/outcome; reports an action-body error with those tags.
      class Appsignal < Adapter
        def self.available? = defined?(::Appsignal) ? true : false

        def record_action(payload, _duration_ms)
          name = transaction_name(payload)
          return unless name

          ::Appsignal.set_action(name)
          ::Appsignal.add_tags(tags(payload))
        end

        def record_error(error, payload)
          ::Appsignal.set_error(error, tags(payload))
        end

        private

        def tags(payload)
          {
            "reactive_component" => payload[:component],
            "reactive_action" => payload[:action],
            "reactive_outcome" => payload[:outcome]&.to_s
          }.compact
        end
      end
    end
  end
end
