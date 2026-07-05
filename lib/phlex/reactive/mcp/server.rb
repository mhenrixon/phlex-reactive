# frozen_string_literal: true

module Phlex
  module Reactive
    module MCP
      # Builds the read-only MCP::Server (issue #168). The tool array is FIXED and
      # FROZEN — there is deliberately no arbitrary-query or mutation tool; every
      # tool reads the loaded registry and reports names/paths/schemas only.
      module Server
        TOOLS = [
          Tools::DoctorTool,
          Tools::ComponentsTool,
          Tools::ActionsTool,
          Tools::FindTool,
          Tools::ConfigTool
        ].freeze

        INSTRUCTIONS = <<~TEXT
          Read-only diagnostic tools for a phlex-reactive install. Use them to
          answer "what reactive components/actions exist, where are they defined,
          is each authorized, and is the install wired correctly?" without grepping.

          - phlex_reactive_doctor: validate the install (route, Stimulus, verifier, …).
          - phlex_reactive_components: the component inventory (names, paths, keys).
          - phlex_reactive_actions: per-action detail (params, source, authorization).
          - phlex_reactive_find: fuzzy search + method-definition source.
          - phlex_reactive_config: a redacted config summary (never secrets/tokens).

          For reference documentation (not live-app introspection) see the hosted
          docs MCP at https://phlex-reactive.zoolutions.llc/llms.txt.
        TEXT

        module_function

        def build
          ::MCP::Server.new(
            name: "phlex-reactive",
            title: "phlex-reactive diagnostics",
            version: Phlex::Reactive::VERSION,
            instructions: INSTRUCTIONS,
            tools: TOOLS.dup
          )
        end
      end
    end
  end
end
