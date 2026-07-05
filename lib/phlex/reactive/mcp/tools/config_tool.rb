# frozen_string_literal: true

module Phlex
  module Reactive
    module MCP
      module Tools
        # phlex_reactive_config — a REDACTED config summary. It reports the
        # page-stable, non-secret configuration a developer needs to understand
        # the install, and NEVER the verifier, secret_key_base, or any token. The
        # allowlist below is explicit: a field is reported only if it appears here.
        class ConfigTool < BaseTool
          tool_name "phlex_reactive_config"
          title "phlex-reactive config"
          description <<~DESC
            A redacted summary of the phlex-reactive configuration: gem version,
            action_path, base_controller_name, renderer, verify_authorized +
            authorization_methods, verbose_errors/debug/log_events, flash_target,
            and whether pgbus is present/streams-capable. NEVER reports the
            verifier, secret_key_base, or any signed token. Read-only.
          DESC

          input_schema(properties: {}, required: [])

          def self.call(server_context: nil) # rubocop:disable Lint/UnusedMethodArgument
            json_response(
              version: Phlex::Reactive::VERSION,
              action_path: Phlex::Reactive.action_path,
              base_controller_name: Phlex::Reactive.base_controller_name,
              renderer: renderer_name,
              verify_authorized: Phlex::Reactive.verify_authorized,
              authorization_methods: Phlex::Reactive.authorization_methods,
              authorization_errors: Phlex::Reactive.authorization_errors.map(&:to_s),
              verbose_errors: Phlex::Reactive.verbose_errors,
              debug: Phlex::Reactive.debug,
              log_events: Phlex::Reactive.log_events,
              flash_target: Phlex::Reactive.flash_target,
              pgbus: pgbus?,
              pgbus_streams: pgbus_streams?
            )
          end

          # The renderer is a controller CLASS (or nil) — report its name, never
          # the object (which could inspect to something with state).
          def self.renderer_name
            renderer = Phlex::Reactive.renderer
            renderer.respond_to?(:name) ? renderer.name : renderer.class.name
          rescue StandardError
            nil
          end

          # Is pgbus present and stream-capable? Delegates to the config readers
          # when they exist; otherwise probes directly (defined? + respond_to?),
          # so the report is correct regardless of pgbus version.
          def self.pgbus?
            return Phlex::Reactive.pgbus? if Phlex::Reactive.respond_to?(:pgbus?)

            !!(defined?(::Pgbus) && ::Pgbus.respond_to?(:stream))
          rescue StandardError
            false
          end

          def self.pgbus_streams?
            return Phlex::Reactive.pgbus_streams? if Phlex::Reactive.respond_to?(:pgbus_streams?)
            return false unless pgbus?

            broadcast = ::Pgbus.stream("").method(:broadcast)
            broadcast.parameters.any? { |_type, name| name == :exclude }
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
