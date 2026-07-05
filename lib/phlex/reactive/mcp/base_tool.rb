# frozen_string_literal: true

require "json"

module Phlex
  module Reactive
    module MCP
      # The base class every phlex-reactive MCP tool subclasses (issue #168),
      # mirroring pgbus's BaseTool. It sets the read-only annotation contract ONCE
      # and overrides annotations_value so subclasses inherit it — MCP::Tool.inherited
      # resets @annotations_value to nil per subclass, so without this each tool
      # would advertise no annotations.
      #
      # Every tool is READ-ONLY and NON-DESTRUCTIVE: it reads the loaded registry
      # (via Inspector / Doctor) and reports NAMES, PATHS, and declared SCHEMAS
      # only — never a token, secret, or runtime state (the instrumentation
      # privacy contract extended to tooling). There is deliberately NO
      # arbitrary-query tool.
      class BaseTool < ::MCP::Tool
        annotations(
          read_only_hint: true,
          destructive_hint: false,
          idempotent_hint: true,
          open_world_hint: false
        )

        class << self
          # Inherit the base annotations into every subclass (MCP::Tool.inherited
          # nils @annotations_value, so fall through to the superclass's).
          def annotations_value
            super || (superclass.respond_to?(:annotations_value) ? superclass.annotations_value : nil)
          end

          # A single text-content response carrying JSON.generate(value). The one
          # place tool output is serialized — pretty-printed for a human reading
          # the transcript, still valid JSON for the client.
          def json_response(value)
            ::MCP::Tool::Response.new([{ type: "text", text: JSON.pretty_generate(value) }])
          end

          # An error response (the tool ran but has nothing to return — e.g. a
          # find with no match handled by the tool, or a bad filter).
          def error_response(message)
            ::MCP::Tool::Response.new([{ type: "text", text: message }], error: true)
          end

          # Populate the Streamable registry the Inspector/Doctor read — the
          # tools call this before introspecting so every app component is
          # loaded. Guarded for a non-Rails / not-yet-booted context.
          def eager_load_app!
            ::Rails.application.eager_load! if defined?(::Rails) && ::Rails.application
          end
        end
      end
    end
  end
end
