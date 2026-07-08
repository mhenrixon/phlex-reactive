# frozen_string_literal: true

module Phlex
  module Reactive
    # Turnkey APM integration (issue #207). The gem already emits `*.phlex_reactive`
    # ActiveSupport::Notifications events (issue #107); this namespace turns them
    # into per-component visibility in AppSignal / Sentry / Datadog with ONE config
    # line — `Phlex::Reactive.apm = :appsignal` — instead of every app hand-writing
    # the subscribe block and each vendor's transaction-naming / error-tagging API.
    #
    # The vendor adapters are RUNTIME capability-detected (`defined?(::Appsignal)`
    # etc.), never a gemspec dependency — the same optionality invariant as pgbus.
    # A set-but-absent SDK logs one warning and no-ops.
    module APM
      # Symbol => built-in adapter class. Resolved lazily (at attach time), so the
      # adapter class is only referenced when an app actually opts into it.
      BUILT_INS = {
        appsignal: "Phlex::Reactive::APM::Appsignal",
        sentry: "Phlex::Reactive::APM::Sentry",
        datadog: "Phlex::Reactive::APM::Datadog"
      }.freeze

      class << self
        # Resolve `Phlex::Reactive.apm` to a live adapter instance, or nil.
        #   * nil            -> nil (off; no warning)
        #   * an object      -> returned verbatim (a custom adapter)
        #   * a known Symbol -> the built-in adapter instance IF its SDK is loaded,
        #                       else nil + one warning
        #   * an unknown Symbol -> nil + one warning
        def detect(apm)
          return nil if apm.nil?
          return apm unless apm.is_a?(Symbol)

          klass_name = BUILT_INS[apm]
          return warn_and_nil("apm = #{apm.inspect} — unknown APM flavour (known: " \
                              "#{BUILT_INS.keys.map(&:inspect).join(", ")})") unless klass_name

          klass = klass_name.constantize
          return klass.new if klass.available?

          warn_and_nil("apm = #{apm.inspect} set but #{apm} is not loaded — no-op. " \
                       "Require the SDK (or remove the setting).")
        end

        # Attach the APM Subscriber to the notification bus if an adapter resolves.
        # Called once from the engine's after_initialize when Phlex::Reactive.apm
        # is set. Idempotent within a boot: a second call with the SAME adapter is
        # a no-op. Returns the attached adapter (or nil when nothing resolved).
        def attach!(apm = Phlex::Reactive.apm)
          adapter = detect(apm)
          return nil unless adapter

          Subscriber.install(adapter)
          # Hold the adapter so the endpoint's error seam (report_error) can reach
          # record_error without re-running detection per request.
          Phlex::Reactive.resolved_apm_adapter = adapter
          adapter
        end

        # Drop the installed subscriber + adapter. Tests only.
        def reset!
          Subscriber.uninstall
          Phlex::Reactive.resolved_apm_adapter = nil
        end

        private

        def warn_and_nil(message)
          logger = Phlex::Reactive.send(:default_logger)
          logger&.warn("[phlex-reactive] #{message}")
          nil
        end
      end
    end
  end
end
