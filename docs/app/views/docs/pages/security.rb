# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Security < DocsUI::Page
        title 'Security & threat model'
        eyebrow 'Guide'

        def lead
          'Every reactive action is a browser-reachable RPC. phlex-reactive makes the safe path the ' \
            'default, but you own the authorization boundary. Read this once.'
        end

        def content
          signature_guarantees
          authorize_rule
          default_deny_rule
          params_rule
          secrets_rule
          csrf_auth
          failure_modes
          failure_ux
          error_flash_ux
          token_lifetime
          checklist
        end

        private

        def signature_guarantees
          DocsUI::Section("What the signature guarantees (and what it doesn't)") do
            DocsUI::Prose() do
              p do
                plain 'The DOM token is a '
                code { 'MessageVerifier' }
                plain '-signed payload:'
              end
              ul do
                li do
                  plain 'Record-backed: '
                  code { '{ "c" => "Todos::Item", "gid" => "gid://app/Todo/42" }' }
                end
                li do
                  plain 'State-backed: '
                  code { '{ "c" => "Counter", "s" => { "count" => 3 } }' }
                end
                li do
                  plain 'Record + state: '
                  code do
                    plain '{ "c" => "Fields::InlineEdit", "gid" => "gid://app/User/7", '
                    plain '"s" => { "attribute" => "name", "editing" => true } }'
                  end
                end
              end
              p do
                plain 'When a component declares both '
                code { 'reactive_record' }
                plain ' and '
                code { 'reactive_state' }
                plain ", the record's GlobalID and the declared state are signed into "
                strong { 'one' }
                plain ' payload — so the transient mode (e.g. which column an inline edit may write) is ' \
                      'tamper-proof alongside the record.'
              end
              p do
                strong { 'Guarantees' }
                plain ' (tampering any of these fails verification → HTTP 400):'
              end
              ul do
                li do
                  plain "The component class can't be swapped (can't point a "
                  code { 'Todo' }
                  plain ' token at an '
                  code { 'AdminUser' }
                  plain ' component).'
                end
                li { plain "The record's GlobalID can't be swapped or forged." }
                li do
                  plain "State values can't be edited — including state signed alongside a record (the client " \
                        "can't switch an inline edit's "
                  code { 'attribute' }
                  plain " to a column it shouldn't touch)."
                end
              end
              p do
                strong { 'Does NOT guarantee' }
                plain ': that '
                strong { 'this user' }
                plain ' may act on this record. The signature proves the token is one '
                strong { 'we' }
                plain ' minted, not that the current session is allowed to mutate the target. '
                strong { 'You must authorize.' }
              end
            end
            # Dogfood: a reactive modal shows what the token actually contains.
            render ReactiveModalComponent.new(modal: 'signed-identity', label: "What's in the token?")
          end
        end

        def authorize_rule
          DocsUI::Section('Rule 1 — authorize inside every mutating action') do
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def rename(title:)
                authorize! @todo, :update?      # Pundit / ActionPolicy / your check
                @todo.update!(title:)
              end
            RUBY
            DocsUI::Prose() do
              p { plain "Register your authorizer's exception so it renders as 403:" }
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
              # or [ActionPolicy::Unauthorized]
            RUBY
            DocsUI::Prose() do
              p do
                plain 'A useful discipline: '
                strong { 'treat an action without an authorize! as a bug' }
                plain " unless it's provably harmless (a view-mode toggle on already-visible data). Consider a " \
                      'RuboCop rule or a code-review checklist for '
                code { 'action' }
                plain '-declared methods.'
              end
            end
          end
        end

        def default_deny_rule
          DocsUI::Section('Rule 2 — actions are default-deny, keep it that way') do
            DocsUI::Prose() do
              p do
                plain 'Only methods declared with '
                code { 'action :name' }
                plain " are invokable. Don't declare an action you don't intend to expose. Public methods without "
                code { 'action' }
                plain " are unreachable, but don't rely on obscurity — declare narrowly."
              end
            end
          end
        end

        def params_rule
          DocsUI::Section('Rule 3 — params are schema-coerced, declare them') do
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              action :rename, params: { title: :string }
              def rename(title:) = @todo.update!(title:)   # only `title`, cast to String
            RUBY
            DocsUI::Prose() do
              p do
                plain 'Anything not in the schema is dropped before reaching your method, so a malicious '
                code { '{ admin: true, title: "x" }' }
                plain ' body can\'t mass-assign. Never do '
                code { '@record.update!(params)' }
                plain ' — take explicit, declared params.'
              end
              p do
                plain 'The schema is compiled once at declaration: a typo\'d type symbol raises '
                code { 'Phlex::Reactive::UnknownParamType' }
                plain ' at class load rather than silently coercing to a string at click time. A declared '
                plain 'value that can\'t be coerced to its type (a bad '
                code { ':date' }
                plain '/'
                code { ':decimal' }
                plain ', a non-file for '
                code { ':file' }
                plain ') is dropped — never fabricated — so the action sees its keyword default, not a bogus value.'
              end
            end
            DocsUI::Callout(:note, title: 'File params (:file / [:file])') do
              plain 'A reactive action can accept an uploaded file (the client switches to multipart FormData when ' \
                    'a file input is present). The multipart request runs through the same gates as a JSON one — ' \
                    'the signed identity is still verified, the action is still default-deny, and the file is still ' \
                    'schema-coerced: a :file param accepts only an actual uploaded file and is dropped for any ' \
                    'non-file value (a forged string can\'t fabricate a file). Apply your own attachment rules in ' \
                    'the action (content-type/size allow-lists, authorize! before attaching) exactly as you would ' \
                    'in a plain controller — the schema proves the value is a file, not that this user may upload it.'
            end
          end
        end

        def secrets_rule
          DocsUI::Section("Rule 4 — don't put secrets in state-backed tokens") do
            DocsUI::Prose() do
              p do
                plain 'State-backed tokens are '
                strong { 'signed' }
                plain ' (tamper-proof) but '
                strong { 'not encrypted' }
                plain " — the values are readable in the DOM (base64). Don't sign secrets into "
                code { 'reactive_state' }
                plain '. For anything sensitive, use '
                code { 'reactive_record' }
                plain ' (only the GlobalID is exposed) and read the sensitive data server-side.'
              end
            end
          end
        end

        def csrf_auth
          DocsUI::Section('CSRF and authentication') do
            DocsUI::Prose() do
              p do
                plain 'The action endpoint inherits from '
                code { 'Phlex::Reactive.base_controller_name' }
                plain ' (default '
                code { 'ActionController::Base' }
                plain '). For a real app:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              Phlex::Reactive.base_controller_name = "ApplicationController"
            RUBY
            DocsUI::Prose() do
              p do
                plain 'This gives you CSRF protection (the client sends '
                code { 'X-CSRF-Token' }
                plain ') and your auth filters. '
                strong { 'Caveat' }
                plain ': if you have '
                strong { 'public' }
                plain ' reactive components (e.g. on a logged-out page) and your '
                code { 'ApplicationController' }
                plain ' force-redirects unauthenticated requests to a login page, the action POST will be ' \
                      'redirected and silently fail. Either:'
              end
              ul do
                li do
                  code { 'skip_before_action :authenticate' }
                  plain ' for the action endpoint (subclass it), or'
                end
                li { plain 'keep public components state-backed and authorize per-action where it matters.' }
              end
            end
          end
        end

        def failure_modes
          DocsUI::Section("The endpoint's failure modes") do
            DocsUI::Prose() do
              ul do
                li do
                  plain 'Tampered / forged / expired token → '
                  code { '400 Bad Request' }
                end
                li do
                  plain 'Undeclared action → '
                  code { '403 Forbidden' }
                end
                li do
                  code { 'authorize!' }
                  plain ' raised (registered error) → '
                  code { '403 Forbidden' }
                end
                li do
                  plain 'Record GlobalID no longer resolves → '
                  code { '404 Not Found' }
                end
                li do
                  plain 'Unknown / non-reactive component class → '
                  code { '400 Bad Request' }
                end
              end
              p do
                plain 'The client runtime logs non-OK responses, applies no DOM change, and dispatches a '
                code { 'reactive:error' }
                plain ' lifecycle event so your UI can react — see below.'
              end
              p do
                plain 'Every failure is warn-logged as '
                code { '[phlex-reactive] …' }
                plain ' in every environment. With '
                code { 'Phlex::Reactive.verbose_errors' }
                plain ' on (the default in development and test via '
                code { 'Rails.env.local?' }
                plain '; off in production), the response also carries a plain-text diagnostic body — the ' \
                      'client prints it via '
                code { 'console.error' }
                plain ' — saying which failure this was: a tampered/stale token, a token class that no longer ' \
                      'resolves, an undeclared action (listing the declared ones), a registered authorization ' \
                      'error, or a GlobalID that no longer finds its record. Param coercion additionally logs ' \
                      'every dropped key with its full bracketed path and reason (undeclared / uncoercible), ' \
                      'with a hint when a flat name looks like the bracketed twin of a declared nested key. ' \
                      'The flag never changes a status — only the body and the logs.'
              end
            end
          end
        end

        def failure_ux
          DocsUI::Section('Failure UX — the lifecycle events') do
            DocsUI::Prose() do
              p do
                plain 'The generic controller dispatches three bubbling, composed '
                code { 'CustomEvent' }
                plain 's around every action round trip, so an app can toast an error, veto a dispatch, ' \
                      'instrument latency, or build retry UI without forking the controller:'
              end
              ul do
                li do
                  code { 'reactive:before-dispatch' }
                  plain ' — cancelable, fired before debounce/enqueue with '
                  code { '{ action, params, element }' }
                  plain '. '
                  code { 'event.preventDefault()' }
                  plain ' skips the round trip entirely (nothing is scheduled).'
                end
                li do
                  code { 'reactive:applied' }
                  plain ' — fired with '
                  code { '{ action, params, html }' }
                  plain ' once the streams were handed to '
                  code { 'Turbo.renderStreamMessage' }
                  plain ' (Turbo applies them asynchronously — for post-morph timing listen to Turbo\'s own events).'
                end
                li do
                  code { 'reactive:error' }
                  plain ' — fired in every failure branch with '
                  code { '{ action, params, kind, status?, body?, retry? }' }
                  plain '; '
                  code { 'kind' }
                  plain ' is one of '
                  code { 'redirected | http | content-type | timeout | offline | network' }
                  plain ' (all retriable) or '
                  code { 'apply' }
                  plain ' — the server already completed the mutation but something AFTER the fetch threw ' \
                        'inside the controller itself (a malformed response, a Turbo render error); it ' \
                        'carries NO '
                  code { 'retry' }
                  plain ', since retrying would re-POST an action that already succeeded. A throwing '
                  code { 'reactive:applied' }
                  plain ' LISTENER is different — the DOM spec never propagates a listener\'s exception ' \
                        'back to '
                  code { 'dispatchEvent' }
                  plain '\'s caller, so it can\'t surface as '
                  code { 'reactive:error' }
                  plain ' at all; it just logs. '
                  code { 'retry()' }
                  plain ' (when present) re-enters the request queue with the freshest token and freshly ' \
                        'collected fields (and no-ops once the component left the DOM).'
                end
              end
            end
            DocsUI::Code(<<~JAVASCRIPT, lexer: :javascript)
              // A page-level toaster: one listener, or plain Stimulus composition —
              // <body data-controller="toast" data-action="reactive:error->toast#show">
              document.addEventListener("reactive:error", ({ detail }) => {
                toast(`Action failed (${detail.kind}${detail.status ? ` ${detail.status}` : ""})`, {
                  onRetry: detail.retry, // re-enqueues with the freshest signed token
                })
              })
            JAVASCRIPT
            DocsUI::Callout(:note, title: 'The events are hooks, not the security boundary') do
              plain 'A 403 still denies the action server-side whether or not anything listens; the existing ' \
                    'console.error logging is unchanged. The events only make the failure visible to your UI.'
            end
            DocsUI::Prose() do
              p do
                plain 'The '
                code { 'timeout' }
                plain ' and '
                code { 'offline' }
                plain ' kinds bound the request itself. '
                code { 'AbortSignal.timeout' }
                plain ' (default 30s, set '
                code { '<meta name="phlex-reactive-timeout">' }
                plain ') aborts a hung request so one dead connection can no longer wedge the component\'s ' \
                      'request queue; an offline click short-circuits BEFORE the fetch (the edit is never ' \
                      'half-sent) and mirrors '
                code { 'data-reactive-offline' }
                plain ' onto '
                code { '<html>' }
                plain ' as a pure CSS hook.'
              end
            end
            DocsUI::Callout(:warning, title: 'A timed-out request may have SUCCEEDED — no auto-replay') do
              plain 'A timeout means the server did not answer in time, NOT that it did nothing — the mutation ' \
                    'may have committed. phlex-reactive never auto-replays, and even a manual retry() can ' \
                    'double-apply a non-idempotent action. Make retryable actions idempotent, or gate retry UI.'
            end
          end
        end

        def error_flash_ux
          DocsUI::Section('Showing the user a failure (error_flash, error bodies, dismiss_after)') do
            DocsUI::Prose() do
              p do
                plain 'The lifecycle events are the hook; these three built-ins are the ready-made surface, ' \
                      'all opt-in and '
                strong { 'status-preserving' }
                plain ' — no flag ever changes an HTTP status.'
              end
              ul do
                li do
                  strong { 'In-action validation replies' }
                  plain ' — a failure the action knows about returns a flash at 200: '
                  code { 'reply.replace.flash(:error, "Title can\'t be blank")' }
                  plain '.'
                end
                li do
                  code { 'Phlex::Reactive.error_flash' }
                  plain ' — a '
                  code { '->(kind) { "message" }' }
                  plain ' lambda. When set, every endpoint rescue path (400/403/404) renders a turbo-stream ' \
                        'flash the user sees, at the SAME status. It composes with '
                  code { 'verbose_errors' }
                  plain ' (the flash wins the body, the diagnostic still logs) and degrades gracefully if the ' \
                        'lambda raises (falls back to the bare/diagnostic body — never a 500).'
                end
                li do
                  strong { 'Non-OK turbo-stream bodies are rendered' }
                  plain ' — the client applies a turbo-stream error body instead of discarding it, and marks ' \
                        'the root '
                  code { 'data-reactive-error="<kind>"' }
                  plain ' (styleable in pure CSS), cleared on the next success.'
                end
                li do
                  code { 'dismiss_after:' }
                  plain ' on '
                  code { 'reply.flash' }
                  plain ' — a document-level handler removes the flash after the timeout, so it self-cleans ' \
                        'reply AND broadcast flashes.'
                end
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # config/initializers/phlex_reactive.rb
              Phlex::Reactive.error_flash = ->(kind) do
                case kind
                when :not_found then "That item is no longer available."
                when :forbidden then "You don't have permission to do that."
                else                 "Something went wrong — please try again."
                end
              end

              # In an action, a self-dismissing validation flash:
              reply.replace.flash(:error, "Couldn't save — try again", dismiss_after: 4000)
            RUBY
            DocsUI::Callout(:note, title: 'A 400 error body never refreshes the held token') do
              plain 'The identity token is not a nonce — it stays retry-valid. The client only adopts a fresh ' \
                    'token from a body that re-renders THIS element\'s id, so an error/foreign body can\'t swap ' \
                    'the token out. This is intentional; do not "fix" it.'
            end
          end
        end

        def token_lifetime
          DocsUI::Section('Token lifetime & rotation') do
            DocsUI::Prose() do
              p do
                plain 'Tokens are signed with '
                code { 'secret_key_base' }
                plain ' (or your '
                code { 'Phlex::Reactive.verifier' }
                plain "). They don't expire by default. If you need expiry, set a verifier with an "
                code { 'expires_in' }
                plain ' policy, or include a server-checked timestamp in state. Rotating '
                code { 'secret_key_base' }
                plain ' invalidates all outstanding tokens (open tabs must reload).'
              end
            end
          end
        end

        def checklist
          DocsUI::Section('Quick checklist') do
            DocsUI::Prose() do
              ul do
                li do
                  plain 'Every mutating action calls '
                  code { 'authorize!' }
                  plain ' (or is provably harmless).'
                end
                li do
                  code { 'Phlex::Reactive.authorization_errors' }
                  plain " includes your authorizer's error."
                end
                li do
                  plain 'Every action with input declares a '
                  code { 'params:' }
                  plain ' schema.'
                end
                li do
                  plain 'No '
                  code { '@record.update!(params)' }
                  plain ' — only declared params.'
                end
                li do
                  plain 'No secrets in '
                  code { 'reactive_state' }
                  plain '; sensitive data uses '
                  code { 'reactive_record' }
                  plain '.'
                end
                li do
                  code { 'base_controller_name' }
                  plain ' set to '
                  code { 'ApplicationController' }
                  plain ' (CSRF + auth).'
                end
                li { plain "Public components don't get redirected to login on the action POST." }
              end
            end
          end
        end
      end
    end
  end
end
