# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Installation < DocsUI::Page
        title 'Installation'
        eyebrow 'Guide'

        def lead
          'Add the gem, run the installer, register one Stimulus controller eagerly — ' \
            'the Rails engine wires up the endpoint and assets for you.'
        end

        def content
          install
          generators
          importmap
          jsbundling
          bun
          requirements
          configuration
          verify
        end

        private

        def install
          DocsUI::Section('Install') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'Gemfile')
              gem "phlex-reactive"
            RUBY
            DocsUI::Code(<<~SHELL, lexer: :shell)
              bundle install
              bin/rails generate phlex:reactive:install
            SHELL
            DocsUI::Prose() do
              p { plain 'The Rails engine automatically:' }
              ul do
                li do
                  plain 'mounts '
                  code { 'POST /reactive/actions' }
                  plain ' → '
                  code { 'Phlex::Reactive::ActionsController#create' }
                end
                li do
                  plain "adds the gem's "
                  code { 'app/javascript' }
                  plain ' to the asset paths'
                end
                li do
                  plain 'auto-pins (and '
                  code { 'preload: true' }
                  plain 's) the client controller for importmap apps'
                end
              end
              p do
                plain 'The '
                strong { 'installer' }
                plain ' ('
                code { 'phlex:reactive:install' }
                plain ') does the host-app wiring:'
              end
              ul do
                li do
                  plain 'registers the '
                  code { 'reactive' }
                  plain ' Stimulus controller eagerly in your entrypoint'
                end
                li do
                  plain 'writes '
                  code { 'config/initializers/phlex_reactive.rb' }
                  plain ' with the common options'
                end
              end
              p do
                plain "If you'd rather wire it by hand, register the controller once (eagerly — below)."
              end
            end
          end
        end

        def generators
          DocsUI::Section('Generators') do
            DocsUI::Code(<<~SHELL, lexer: :shell)
              # Setup (idempotent)
              bin/rails generate phlex:reactive:install

              # Scaffold a state-backed component (record-less)
              bin/rails generate phlex:reactive:component Counter increment decrement

              # Scaffold a record-backed component (signed GlobalID identity)
              bin/rails generate phlex:reactive:component Todos::Item toggle rename --record todo

              # Custom signed state vars
              bin/rails generate phlex:reactive:component Wizard next_step --state step open
            SHELL
            DocsUI::Prose() do
              p do
                plain 'The component generator also writes an RSpec spec when your app has a '
                code { 'spec/' }
                plain ' directory.'
              end
            end
          end
        end

        def importmap
          DocsUI::Section('importmap-rails (default Rails 7+)') do
            DocsUI::Code(<<~JS, lexer: :javascript, filename: 'app/javascript/controllers/index.js')
              import { application } from "controllers/application"
              import ReactiveController from "phlex/reactive/reactive_controller"
              application.register("reactive", ReactiveController)
            JS
            DocsUI::Callout(:warning, title: 'Register eagerly, not lazily') do
              plain 'If you '
              code { 'lazyLoadControllersFrom' }
              plain ', the controller is fetched on first appearance — and a user who clicks ' \
                    'immediately after load can fire before it connects, so nothing happens. Eager ' \
                    "registration (above) guarantees it's bound before any interaction. The engine " \
                    'already preloads the asset, so this adds no latency.'
            end
          end
        end

        def jsbundling
          DocsUI::Section('esbuild / rollup / webpack (jsbundling)') do
            DocsUI::Code(<<~JS, lexer: :javascript, filename: 'app/javascript/controllers/index.js')
              import { application } from "./application"
              import ReactiveController from "phlex/reactive/reactive_controller"
              application.register("reactive", ReactiveController)
            JS
            DocsUI::Prose() do
              p do
                plain "If your bundler can't resolve the gem path, copy the file in:"
              end
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              cp "$(bundle show phlex-reactive)/app/javascript/phlex/reactive/reactive_controller.js" \\
                 app/javascript/controllers/reactive_controller.js
            SHELL
            DocsUI::Prose() do
              p do
                plain '…and '
                code { 'import ReactiveController from "./reactive_controller"' }
                plain '.'
              end
              p do
                plain 'Importing '
                code { 'reactive_controller.js' }
                plain ' also registers the '
                code { 'reactive:visit' }
                plain ' Turbo '
                code { 'StreamAction' }
                plain ' that powers '
                code { 'reply.redirect' }
                plain '. The '
                code { 'import ReactiveController' }
                plain " above covers this; if you vendor the file, make sure it's actually imported " \
                      "(not tree-shaken away) or redirects won't fire."
              end
            end
          end
        end

        def bun
          DocsUI::Section('bun (bun-rails)') do
            DocsUI::Prose() do
              p do
                plain 'Same as esbuild. Point the import at the gem path or vendor the file.'
              end
            end
          end
        end

        def requirements
          DocsUI::Section('Requirements') do
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Rails' }
                  plain ' ≥ 7.1'
                end
                li do
                  strong { 'Phlex 2' }
                  plain ' via '
                  code { 'phlex-rails' }
                  plain ', with an '
                  code { 'ApplicationComponent < Phlex::HTML' }
                  plain ' base class that includes the Phlex Rails helpers ('
                  code { 'dom_id' }
                  plain ', '
                  code { 't' }
                  plain ', routes, etc.)'
                end
                li do
                  strong { 'Turbo' }
                  plain ' ≥ 8 (for morphing) — '
                  code { 'turbo-rails' }
                  plain ', with '
                  code { 'window.Turbo' }
                  plain ' available'
                end
                li do
                  plain 'A '
                  code { '<meta name="csrf-token">' }
                  plain ' in your layout (standard Rails)'
                end
                li do
                  strong { 'pgbus' }
                  plain ' (optional, recommended) for reliable broadcasting'
                end
              end
            end
          end
        end

        def configuration
          DocsUI::Section('Configuration') do
            DocsUI::Prose() do
              p do
                plain 'Create '
                code { 'config/initializers/phlex_reactive.rb' }
                plain ' as needed:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/initializers/phlex_reactive.rb')
              Phlex::Reactive.base_controller_name = "ApplicationController"   # CSRF + auth + Current
              Phlex::Reactive.renderer             = ApplicationController     # app helpers during render
              Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
              # Phlex::Reactive.action_path = "/_r/actions"                   # custom endpoint
              # Phlex::Reactive.verifier    = ActiveSupport::MessageVerifier.new(ENV["REACTIVE_KEY"])
              # Phlex::Reactive.flash_target = "flash"                         # DOM id reply…flash appends into
              # Phlex::Reactive.flash_component = MyFlash                      # renders string flashes: new(level:, content:)
            RUBY
            DocsUI::Prose() do
              p do
                plain 'If you change '
                code { 'action_path' }
                plain ', expose it to the client:'
              end
            end
            DocsUI::Code(<<~ERB, lexer: :erb)
              <meta name="phlex-reactive-action-path" content="<%= Phlex::Reactive.action_path %>">
            ERB
          end
        end

        def verify
          DocsUI::Section('Verify it works') do
            DocsUI::Prose() do
              p do
                plain 'Run the doctor — it validates the whole install (route, Stimulus registration, ' \
                      'CSRF, the identity verifier, and every component) and prints '
                code { '✓/✗/?' }
                plain ' with a fix for each failure:'
              end
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              bin/rails phlex_reactive:doctor
            SHELL
            DocsUI::Prose() do
              p do
                plain 'Then drop a counter on any page, click '
                code { '+' }
                plain ', and watch it increment with no full-page reload. If it reloads or does ' \
                      'nothing, check the testing guide troubleshooting section.'
              end
            end
            DocsUI::Callout(:tip) do
              plain 'The doctor is read-only and safe to run anywhere. A '
              code { '✗' }
              plain ' points at the exact fix; a '
              code { '?' }
              plain ' is advisory (e.g. it can’t confirm csrf_meta_tags in a Phlex-only layout). ' \
                    'No full-page reload on the click is the runtime signal everything is wired.'
            end
          end
        end
      end
    end
  end
end
