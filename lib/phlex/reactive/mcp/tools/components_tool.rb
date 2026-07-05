# frozen_string_literal: true

module Phlex
  module Reactive
    module MCP
      module Tools
        # phlex_reactive_components — a summary of every constant-backed reactive
        # component: name, source path, action count, record/state keys. The
        # bird's-eye inventory; phlex_reactive_actions has the per-action detail.
        class ComponentsTool < BaseTool
          tool_name "phlex_reactive_components"
          title "phlex-reactive components"
          description <<~DESC
            List every reactive component in the app with its name, source
            file:line, action count, and record/state keys. Use phlex_reactive_actions
            for the full per-action detail, or phlex_reactive_find to search.
            Read-only — names, paths, and declared keys only.
          DESC

          input_schema(properties: {}, required: [])

          def self.call(server_context: nil) # rubocop:disable Lint/UnusedMethodArgument
            ::Rails.application.eager_load! if defined?(::Rails) && ::Rails.application
            components = Phlex::Reactive::Inspector.components.map do
              {
                name: it.name,
                path: Phlex::Reactive::Inspector::Report.location_str(it.path),
                action_count: it.actions.length,
                record_key: it.record_key,
                state_keys: it.state_keys
              }
            end
            json_response(components: components)
          end
        end
      end
    end
  end
end
