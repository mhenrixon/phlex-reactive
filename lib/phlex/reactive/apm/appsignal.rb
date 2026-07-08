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

        # Report the error with tags. AppSignal 4.x removed the positional
        # tags/namespace args from set_error and requires the BLOCK form
        # (set_error(error) { add_tags(...) }); 3.x accepts the positional hash.
        # Branch on the method's arity so the adapter works on both majors without
        # pinning a version — the capability-detection posture applied within a gem.
        def record_error(error, payload)
          if set_error_takes_tags?
            ::Appsignal.set_error(error, tags(payload))
          else
            ::Appsignal.set_error(error) { ::Appsignal.add_tags(tags(payload)) }
          end
        end

        private

        # True on AppSignal 3.x, where set_error accepts a positional tags arg
        # (arity != 1). On 4.x set_error takes only the error (arity 1) + a block.
        def set_error_takes_tags?
          ::Appsignal.method(:set_error).arity != 1
        end

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
