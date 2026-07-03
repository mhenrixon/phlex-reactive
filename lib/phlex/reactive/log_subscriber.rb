# frozen_string_literal: true

require "active_support/log_subscriber"

module Phlex
  module Reactive
    # Opt-in LogSubscriber (issue #107): turns each hot-path event into ONE
    # compact debug line, so a developer can watch reactive traffic in the log
    # without an APM:
    #
    #   [reactive] Counter#increment ok (3.1ms)
    #   [reactive] Counter#drop_table denied_undeclared (0.2ms)
    #   [reactive] render Counter 512B (0.9ms)
    #   [reactive] broadcast replace Counter →2 (1.4ms)
    #
    # Default OFF — the events fire for APMs regardless of this; attaching the
    # subscriber only adds the gem's own log lines. The engine attaches it once
    # at boot when Phlex::Reactive.log_events is true. Lines are logged at DEBUG,
    # so they're invisible unless the app's log level allows it.
    #
    # Payloads carry NAMES/outcome/sizes ONLY (never token/params/state), so
    # these lines can never leak a secret. A :invalid_token event has no trusted
    # component name (the token didn't verify), so the line omits the `Class#`
    # prefix rather than echo an unverified class.
    class LogSubscriber < ::ActiveSupport::LogSubscriber
      def action(event)
        return unless logger.debug?

        payload = event.payload
        subject =
          if payload[:component]
            "#{payload[:component]}##{payload[:action]}"
          else
            # No trusted component (invalid token) — name the action alone.
            payload[:action]
          end
        debug { "[reactive] #{subject} #{payload[:outcome]} (#{round(event.duration)}ms)" }
      end

      def render(event)
        return unless logger.debug?

        payload = event.payload
        debug { "[reactive] render #{payload[:component]} #{payload[:bytesize]}B (#{round(event.duration)}ms)" }
      end

      def broadcast(event)
        return unless logger.debug?

        payload = event.payload
        debug do
          "[reactive] broadcast #{payload[:stream_action]} #{payload[:component]} " \
            "→#{payload[:streamables]} (#{round(event.duration)}ms)"
        end
      end

      private

      def round(duration_ms)
        duration_ms.round(1)
      end
    end
  end
end
