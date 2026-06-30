# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Security < Views::Docs::Page
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
          token_lifetime
          checklist
        end

        private

        def signature_guarantees
          render Views::Docs::Section.new("What the signature guarantees (and what it doesn't)") do
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new('Rule 1 — authorize inside every mutating action') do
            render Views::Code.new(<<~RUBY, lexer: :ruby)
              def rename(title:)
                authorize! @todo, :update?      # Pundit / ActionPolicy / your check
                @todo.update!(title:)
              end
            RUBY
            render Views::Docs::Prose.new do
              p { plain "Register your authorizer's exception so it renders as 403:" }
            end
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
              # or [ActionPolicy::Unauthorized]
            RUBY
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new('Rule 2 — actions are default-deny, keep it that way') do
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new('Rule 3 — params are schema-coerced, declare them') do
            render Views::Code.new(<<~RUBY, lexer: :ruby)
              action :rename, params: { title: :string }
              def rename(title:) = @todo.update!(title:)   # only `title`, cast to String
            RUBY
            render Views::Docs::Prose.new do
              p do
                plain 'Anything not in the schema is dropped before reaching your method, so a malicious '
                code { '{ admin: true, title: "x" }' }
                plain ' body can\'t mass-assign. Never do '
                code { '@record.update!(params)' }
                plain ' — take explicit, declared params.'
              end
            end
            render Views::Docs::Callout.new(:note, title: 'File params (:file / [:file])') do
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
          render Views::Docs::Section.new("Rule 4 — don't put secrets in state-backed tokens") do
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new('CSRF and authentication') do
            render Views::Docs::Prose.new do
              p do
                plain 'The action endpoint inherits from '
                code { 'Phlex::Reactive.base_controller_name' }
                plain ' (default '
                code { 'ActionController::Base' }
                plain '). For a real app:'
              end
            end
            render Views::Code.new(<<~RUBY, lexer: :ruby)
              Phlex::Reactive.base_controller_name = "ApplicationController"
            RUBY
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new("The endpoint's failure modes") do
            render Views::Docs::Prose.new do
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
              p { plain 'The client runtime logs non-OK responses and applies no DOM change.' }
            end
          end
        end

        def token_lifetime
          render Views::Docs::Section.new('Token lifetime & rotation') do
            render Views::Docs::Prose.new do
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
          render Views::Docs::Section.new('Quick checklist') do
            render Views::Docs::Prose.new do
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
