# frozen_string_literal: true

module Phlex
  module Reactive
    # The read-only diagnostic MCP server (issue #168): a stdio server exposing
    # five read-only tools (doctor, components, actions, find, config) so Claude
    # Code inside a HOST app can introspect the live reactive registry when
    # debugging. It mirrors pgbus's MCP subtree.
    #
    # The `mcp` gem is OPTIONAL and NEVER a gemspec runtime dependency — this
    # whole subtree references the optional gem's constants (MCP::Tool,
    # MCP::Server), so it is kept OUT of the Zeitwerk loader (loader.ignore in
    # lib/phlex/reactive.rb) and loaded explicitly via MCP.load!.
    #
    #   Phlex::Reactive::MCP.load!         # lazy-require the gem + the tool tree
    #   Phlex::Reactive::MCP::Runner.run   # drive the stdio transport
    #
    # Entry point for a host app: `bin/rails phlex_reactive:mcp` (a rake task, not
    # an exe — introspection needs the booted Rails app). Consumer .mcp.json:
    #
    #   { "mcpServers": { "phlex-reactive": {
    #       "command": "bin/rails", "args": ["phlex_reactive:mcp"] } } }
    module MCP
      # Every file under lib/phlex/reactive/mcp/, in DEPENDENCY ORDER (base_tool
      # before the tools that subclass it; the tools before the server that lists
      # them; the server before the runner that builds it). Loaded by load! after
      # the optional gem itself.
      REQUIRES = %w[
        phlex/reactive/mcp/base_tool
        phlex/reactive/mcp/tools/doctor_tool
        phlex/reactive/mcp/tools/components_tool
        phlex/reactive/mcp/tools/actions_tool
        phlex/reactive/mcp/tools/find_tool
        phlex/reactive/mcp/tools/config_tool
        phlex/reactive/mcp/server
        phlex/reactive/mcp/runner
      ].freeze

      module_function

      # Lazy-require the optional `mcp` gem, then the tool tree in dependency
      # order. Idempotent (plain require). ONLY `require "mcp"` is rescued — a
      # LoadError from an internal path propagates verbatim so a typo isn't
      # masked as "add the mcp gem".
      def load!
        begin
          require "mcp"
        rescue LoadError
          raise Phlex::Reactive::Error,
            "The phlex-reactive MCP diagnostic server needs the `mcp` gem. " \
            "Add `gem \"mcp\"` to your Gemfile (a dev/test group is fine) and run `bundle install`."
        end

        REQUIRES.each { require it }
      end
    end
  end
end
