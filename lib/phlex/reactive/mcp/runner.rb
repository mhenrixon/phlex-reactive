# frozen_string_literal: true

module Phlex
  module Reactive
    module MCP
      # Drives the read-only MCP server over stdio (issue #168). Invoked by the
      # `phlex_reactive:mcp` rake task after MCP.load!.
      #
      # KNOWN CONSTRAINT (same as pgbus): stdio MCP requires a CLEAN stdout — the
      # JSON-RPC frames are the ONLY thing that may be written there. An
      # initializer that `puts` (or any library that writes to $stdout) breaks the
      # transport. Log to $stderr or Rails.logger, never $stdout.
      module Runner
        module_function

        def run
          server = Server.build
          transport = ::MCP::Server::Transports::StdioTransport.new(server)
          transport.open
        end
      end
    end
  end
end
