# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Testing < DocsUI::Page
        title 'Testing reactive components'
        eyebrow 'Guide'

        def lead
          'Reactive components are plain Ruby objects with a few extra class methods, so most testing is ' \
            'fast unit testing — three layers, cheapest first.'
        end

        def content
          unit_actions
          unit_identity
          integration_endpoint
          system_browser
          client_unit
          troubleshooting
        end

        private

        def unit_actions
          DocsUI::Section('1. Unit: actions are just methods') do
            DocsUI::Prose() do
              p { plain 'Build the component, call the action, assert the state changed. No HTTP, no browser.' }
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              test "toggle flips done" do
                todo = todos(:write_docs)         # done: false
                component = Todos::Item.new(todo:)
                component.toggle
                assert todo.reload.done?
              end
            RUBY
          end
        end

        def unit_identity
          DocsUI::Section('2. Unit: the identity token round-trips') do
            DocsUI::Prose() do
              p { plain 'Verify the signed token rebuilds the same component (and that tampering fails).' }
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              test "record-backed identity round-trips" do
                todo = todos(:write_docs)
                token = Todos::Item.new(todo:).send(:reactive_token)

                payload = Phlex::Reactive.verify(token)
                assert_equal "Todos::Item", payload["c"]

                rebuilt = Todos::Item.from_identity(payload)
                assert_equal todo, rebuilt.instance_variable_get(:@todo)
              end

              test "tampered token is rejected" do
                token = Counter.new(count: 1).send(:reactive_token)
                assert_nil Phlex::Reactive.verify(token + "x")
              end
            RUBY
          end
        end

        def integration_endpoint
          DocsUI::Section('3. Integration: the action endpoint') do
            DocsUI::Prose() do
              p do
                plain 'POST a signed token to '
                code { '/reactive/actions' }
                plain ' and assert the turbo-stream response. Mint the token the same way the component does.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              test "increment action returns a turbo-stream replace" do
                token = Counter.new(count: 1).send(:reactive_token)

                post "/reactive/actions",
                  params: { token:, act: "increment" }.to_json,
                  headers: { "Content-Type" => "application/json",
                             "Accept" => "text/vnd.turbo-stream.html" }

                assert_response :success
                assert_match %r{<turbo-stream action="replace" target="counter">}, response.body
                assert_match %r{>2<}, response.body   # count incremented 1 -> 2
              end

              test "undeclared action is forbidden" do
                token = Counter.new(count: 1).send(:reactive_token)
                post "/reactive/actions",
                  params: { token:, act: "drop_table" }.to_json,
                  headers: { "Content-Type" => "application/json" }
                assert_response :forbidden
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'For authorization, stub the current user / policy and assert '
                code { ':forbidden' }
                plain ' when the action\'s '
                code { 'authorize!' }
                plain ' should deny.'
              end
              p do
                plain 'When an action returns a '
                code { 'reply.<verb>' }
                plain ', assert on the streams it produces:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              test "failed update keeps the replace and appends a flash" do
                # POST a save action with invalid input
                assert_response :success
                assert_match %r{<turbo-stream action="replace" target="counter">}, response.body  # token refreshes
                assert_match %r{<turbo-stream action="append" target="flash">}, response.body     # flash appended
              end

              test "remove action emits a remove and no replace" do
                assert_response :success
                assert_match %r{<turbo-stream action="remove" target="todo_42">}, response.body
                refute_match %r{action="replace"}, response.body   # render_self? is false for remove
              end

              test "redirect rides a 200 reactive:visit, not a 3xx" do
                assert_response :success            # NOT :redirect — the client bails on response.redirected
                assert_match %r{<turbo-stream action="reactive:visit" data-url=".*/articles/}, response.body
              end
            RUBY
            DocsUI::Prose() do
              p do
                code { 'reply.<verb>' }
                plain ' is a plain value object — unit-test it with no HTTP: '
                code { 'c.reply.remove.render_self?' }
                plain ' is '
                code { 'false' }
                plain '; '
                code { 'c.reply.replace.flash(:x, "hi").streams.size' }
                plain ' is '
                code { '2' }
                plain '.'
              end
            end
          end
        end

        def system_browser
          DocsUI::Section('4. System / browser: the full loop & broadcasts') do
            DocsUI::Prose() do
              p do
                plain 'Use a system test (Capybara) or a browser-automation CLI for the end-to-end loop ' \
                      'and cross-tab broadcasts. The key assertions:'
              end
              ul do
                li do
                  plain 'Clicking a trigger updates the component '
                  strong { 'without a full page reload' }
                  plain ' (assert a value set on '
                  code { 'window' }
                  plain ' survives the interaction).'
                end
                li { plain 'A change in one session appears in another subscribed session.' }
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # system test sketch
              test "counter increments without reload" do
                visit counter_path
                page.execute_script("window.__marker = 'alive'")
                click_button "+"
                assert_selector "#counter .value", text: "1"
                assert_equal "alive", page.evaluate_script("window.__marker")  # no reload
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'For cross-tab, open two sessions (two '
                code { 'Capybara::Session' }
                plain 's or two browser contexts), act in one, and assert the morph appears in the other. ' \
                      'Allow a beat for the SSE round trip.'
              end
            end
          end
        end

        def client_unit
          DocsUI::Section('5. Client unit tests (bun)') do
            DocsUI::Prose() do
              p do
                plain 'Some client-runtime contracts are timing-sensitive and a full browser can mask them — ' \
                      'e.g. a '
                code { 'submit' }
                plain ' trigger must '
                code { 'preventDefault()' }
                plain ' '
                strong { 'synchronously' }
                plain ' during the event, which a system test in a minimal app can\'t reliably reproduce. ' \
                      'Those are covered by fast bun unit tests against the controller in isolation:'
              end
            end
            DocsUI::Code('bun test spec/javascript     # or: bun run test', lexer: :shell)
            DocsUI::Prose() do
              p do
                plain 'They stub '
                code { '@hotwired/stimulus' }
                plain ' and assert behavior directly (e.g. '
                code { 'dispatch()' }
                plain ' calls '
                code { 'preventDefault()' }
                plain ' before its queued work). CI runs them in the System job, which already has bun set up. ' \
                      'The system suite drives a '
                strong { 'vendored copy' }
                plain ' of the controller ('
                code { 'spec/dummy/public/vendor/reactive_controller.js' }
                plain '); a guard spec keeps it byte-identical to source, so edit the source and re-sync, ' \
                      'never the copy.'
              end
            end
          end
        end

        def troubleshooting
          DocsUI::Section('Troubleshooting') do
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Click does nothing, count stays 0' }
                  plain ' — the controller lazy-loaded and you clicked before connect. Register '
                  code { 'reactive' }
                  plain ' '
                  strong { 'eagerly' }
                  plain '.'
                end
                li do
                  strong { 'Click reloads the whole page' }
                  plain ' — a bare '
                  code { '<button>' }
                  plain ' defaulted to '
                  code { 'type=submit' }
                  plain ' in a form. '
                  code { 'on(:click)' }
                  plain ' already sets '
                  code { 'type=button' }
                  plain '; ensure you spread it.'
                end
                li do
                  strong { '403 from the endpoint' }
                  plain ' — undeclared action, or '
                  code { 'authorize!' }
                  plain ' denied. Declare the '
                  code { 'action' }
                  plain '; check the policy.'
                end
                li do
                  strong { '400 from the endpoint' }
                  plain ' — token tampered, or the '
                  code { 'action' }
                  plain ' key collided. Use the '
                  code { 'act' }
                  plain ' wire key (the gem does); don\'t rename it.'
                end
                li do
                  strong { 'Rapid clicks lose updates' }
                  plain ' — (shouldn\'t happen) a stale-token race. The runtime queues + threads tokens; ' \
                        'file a bug with a repro.'
                end
                li do
                  strong { 'Cross-tab not syncing' }
                  plain ' — subscriber/broadcaster stream keys differ. Pass the '
                  strong { 'same raw *streamables' }
                  plain ' to '
                  code { 'turbo_stream_from' }
                  plain ' and '
                  code { 'broadcast_*_to' }
                  plain '.'
                end
                li do
                  strong { 'Action POST redirected to /sign_in' }
                  plain ' — an auth filter on a public component. '
                  code { 'skip_before_action :authenticate' }
                  plain ' on the endpoint, or keep it state-backed.'
                end
              end
            end
          end
        end
      end
    end
  end
end
