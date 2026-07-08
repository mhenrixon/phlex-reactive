# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # Observability & APM (issue #207): the `*.phlex_reactive` event stream, the
      # turnkey `Phlex::Reactive.apm =` adapters (AppSignal/Sentry/Datadog), the
      # action-body error seam (report with context, re-raise), the bundled
      # LogSubscriber, and the by-hand subscribe path.
      class Observability < DocsUI::Page
        title 'Observability & APM'
        eyebrow 'Guide'

        def lead
          'See reactive traffic at the component level: every action, render, and ' \
            'broadcast is an ActiveSupport::Notifications event, and one config line ' \
            'wires AppSignal, Sentry, or Datadog to name transactions and report ' \
            'errors with context.'
        end

        def content
          events
          apm_adapters
          error_reporting
          log_subscriber
          diy_subscribe
        end

        private

        def events
          DocsUI::Section('The events') do
            md <<~MD
              Every reactive hot path emits an `ActiveSupport::Notifications` event
              under the `phlex_reactive` namespace, so any subscriber — an APM, a
              metric, your own log line — sees which **component and action** a request
              was, how long a render took, and how far a broadcast fanned out. Four
              events fire:

              | Event | Fires | Payload |
              |-------|-------|---------|
              | `action.phlex_reactive` | once per action request | `component`, `action`, `outcome` |
              | `render.phlex_reactive` | per component render | `component`, `bytesize` |
              | `broadcast.phlex_reactive` | per `broadcast_to` call (Action Cable **and** pgbus) | `component`, `stream_action`, `streamables` |
              | `defer.phlex_reactive` | once per deferred render | `component`, `outcome` |

              The `action` `outcome` is one of `ok` / `denied_undeclared` /
              `invalid_token` / `not_found` / `unauthorized` / `unverified` / `error`
              (an uncaught action-body crash). The `defer` `outcome` is `ok` /
              `no_content` / `invalid_token` / `not_found` / `unauthorized` / `error`.
            MD
            DocsUI::Callout(:warning) do
              strong { 'Payloads carry names, the outcome, and sizes only' }
              plain ' — never the token, the params, or component state, so an event ' \
                    'can never leak a secret. An '
              code { 'invalid_token' }
              plain ' event has no trusted component name (the token did not verify), so it is omitted.'
            end
          end
        end

        def apm_adapters
          DocsUI::Section('Turnkey APM adapters') do
            md <<~MD
              Subscribing by hand (below) is the DIY path. For the common trackers
              there's a one-liner that both **names the transaction** and **reports
              errors** — so reactive traffic stops rolling into one blurry
              `ActionsController#create` transaction and a crash arrives at your tracker
              with context:
            MD
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.apm = :appsignal   # or :sentry, :datadog, or a custom object
            RUBY
            md <<~MD
              With it set:

              - Each reactive action shows in the APM as its **own** transaction/span —
                `Counter#increment`, not `Phlex::Reactive::ActionsController#create` —
                tagged with the component, action, and outcome.
              - An action body that raises a genuine error (a 500, not a registered 4xx)
                is **reported to the tracker with `component` / `action` tags**, then
                re-raised unchanged so Rails' own error reporting still fires.

              The SDK is **runtime-detected** — no gem dependency is added, the same
              optionality invariant as pgbus. If the named SDK isn't loaded, `apm =`
              logs one warning at boot and no-ops. A custom object works too — anything
              responding to `record_action(payload, duration_ms)` and
              `record_error(error, payload)`:
            MD
            DocsUI::Code(<<~'RUBY', lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              # Any object with the two-method contract integrates any tool.
              class MyStatsdApm
                def record_action(payload, duration_ms)
                  StatsD.timing("reactive.#{payload[:outcome]}", duration_ms,
                    tags: ["component:#{payload[:component]}", "action:#{payload[:action]}"])
                end

                def record_error(error, payload)
                  StatsD.increment("reactive.error",
                    tags: ["component:#{payload[:component]}", "action:#{payload[:action]}"])
                end
              end

              Phlex::Reactive.apm = MyStatsdApm.new
            RUBY
            DocsUI::Callout(:note) do
              plain 'The adapter is resolved once, at boot (the engine\'s '
              code { 'after_initialize' }
              plain '), so the vendor SDK is loaded by then. Detection is deferred to ' \
                    'that point on purpose — load order doesn\'t matter, and the setting ' \
                    'can live anywhere in your initializer.'
            end
          end
        end

        def error_reporting
          DocsUI::Section('Errors: reported with context, never swallowed') do
            md <<~MD
              A component action that raises a **previously-uncaught** error (a genuine
              500 — not one of the registered 4xx cases like an authorization error) is
              now _observed_ at the endpoint before it propagates. In order:

              1. the `action.phlex_reactive` event is tagged `outcome: :error`;
              2. the exception is reported to the resolved APM adapter **and** every
                 registered `on_action_error` hook, with the name-only
                 `{ component:, action: }` context;
              3. the `error_flash` renders (if configured), so the user sees a flash on
                 a crash — 500s now flow through the same path the 4xx errors already
                 used;
              4. the error is **re-raised unchanged**, so Rails' own error reporting and
                 your middleware fire exactly as before.

              The status never changes, and the existing 4xx rescues are untouched.
              Every reporter is isolated: a broken reporter (or a raising `error_flash`
              lambda) can never turn one 500 into a different 500, or swallow the
              original.

              For a tracker with no built-in adapter, report errors yourself — this hook
              fires on any uncaught action-body error, **without** choosing an `apm`
              symbol:
            MD
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.on_action_error do |error, ctx|
                Honeybadger.notify(error, context: { component: ctx[:component], action: ctx[:action] })
              end
            RUBY
            md <<~MD
              And to show the user a flash when an action crashes — the **same** hook
              the 4xx errors already use (`kind` is `:error` for a crash):
            MD
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.error_flash = ->(kind) { "Something went wrong — please retry." }
            RUBY
          end
        end

        def log_subscriber
          DocsUI::Section('Watch traffic in your own log (no APM)') do
            md <<~MD
              To watch reactive traffic in your log without an APM, flip on the bundled
              `LogSubscriber` (default off). It logs one compact line per event at DEBUG:
            MD
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.log_events = true
              # [reactive] Counter#increment ok (3.1ms)
              # [reactive] Counter#drop_table denied_undeclared (0.2ms)
              # [reactive] render Counter 512B (0.9ms)
              # [reactive] broadcast replace Counter →2 (1.4ms)
              # [reactive] defer SlowTotals ok (18.2ms)
            RUBY
            DocsUI::Callout(:tip) do
              plain 'The events fire whether or not you enable the LogSubscriber — the ' \
                    "flag only controls the gem's own log lines. An unsubscribed instrument " \
                    'is cheap (a few objects per call, zero retained), so the hot paths ' \
                    'carry it unconditionally.'
            end
          end
        end

        def diy_subscribe
          DocsUI::Section('Subscribe by hand') do
            md <<~MD
              The adapters are a convenience over the raw event stream. You can always
              subscribe directly, exactly as you would for any Rails notification:
            MD
            DocsUI::Code(<<~'RUBY', lexer: :ruby, filename: 'config/initializers/phlex_reactive_apm.rb')
              ActiveSupport::Notifications.subscribe('action.phlex_reactive') do |*args|
                event = ActiveSupport::Notifications::Event.new(*args)
                # event.payload => { component:, action:, outcome: }
                # event.duration => ms
                MyAPM.record("reactive.#{event.payload[:outcome]}", event.duration,
                  component: event.payload[:component], action: event.payload[:action])
              end
            RUBY
          end
        end
      end
    end
  end
end
