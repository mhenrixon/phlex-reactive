# frozen_string_literal: true

module Phlex
  module Reactive
    module MCP
      module Tools
        # phlex_reactive_doctor — the install validator's checks as structured
        # JSON (name/status/message/fix), the same data `bin/rails
        # phlex_reactive:doctor` prints as text.
        class DoctorTool < BaseTool
          tool_name "phlex_reactive_doctor"
          title "phlex-reactive doctor"
          description <<~DESC
            Validate the phlex-reactive install and return each check as structured
            JSON: name, status (ok/fail/unknown), message, and a fix line for any
            non-passing check. The same checks `bin/rails phlex_reactive:doctor`
            prints — route, Stimulus registration, csrf, verifier round-trip, base
            controller, every action has a method, stable #id, and the advisory
            authorization heuristic. Read-only.
          DESC

          input_schema(properties: {}, required: [])

          def self.call(server_context: nil) # rubocop:disable Lint/UnusedMethodArgument
            eager_load_app!
            doctor = Phlex::Reactive::Doctor.new
            checks = doctor.checks.map do
              { name: it.name, status: it.status, message: it.message, fix: it.fix }
            end
            json_response(checks: checks, ok: !doctor.failures?)
          end
        end
      end
    end
  end
end
