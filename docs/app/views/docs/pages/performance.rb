# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Performance < DocsUI::Page
        title 'Performance'
        eyebrow 'Guide'

        def lead
          'phlex-reactive aims to be fast in the places that run on every interaction — the re-render, ' \
            'the token signing, the param coercion, and the client hot path.'
        end

        def content
          overview
          hot_paths
          measuring
          before_change
          numbers
          ci
          every_change
          adding_a_benchmark
        end

        private

        def overview
          DocsUI::Section('What we optimize') do
            DocsUI::Prose() do
              p do
                plain 'phlex-reactive aims to be fast in the places that run on every interaction: the '
                plain 'component re-render, the identity-token signing, the param coercion, and the client '
                plain 'request hot path. This page documents how those paths are kept fast, how to measure '
                plain 'them yourself, and how performance is part of every change.'
              end
              p do
                plain 'The honest summary: the re-render is the part we control and the part we optimized '
                plain 'hardest, but a full HTTP action is dominated by the Rails middleware stack and (for '
                plain 'record-backed components) the database — so the render wins matter most for '
                strong { 'broadcasts' }
                plain ', which have no HTTP overhead to amortize against. To be precise about the fan-out: '
                plain 'a '
                code { 'broadcast_*_to' }
                plain ' call renders the component '
                strong { 'once' }
                plain ' and hands the finished HTML to the transport, so every subscriber of that stream '
                plain 'shares one payload (the per-subscriber cost is transport-side, not a render). The '
                plain 'render cost multiplies per '
                strong { 'call' }
                plain ': pushing one change to K different stream keys is K builds + K renders + K token '
                plain 'signings of byte-identical HTML — and per-viewer content ('
                code { 'visible_to:' }
                plain '-style rendering) is the irreducible render-per-viewer case. Measure before you '
                plain 'optimize; the harness below exists so you never have to guess.'
              end
            end
          end
        end

        def hot_paths
          DocsUI::Section('The hot paths') do
            DocsUI::Prose() do
              ul do
                li do
                  code { 'render_component' }
                  plain ' — every action re-render and every broadcast render. Renders through '
                  plain "phlex-rails' lightweight "
                  code { '#render_in' }
                  plain ' against a memoized off-request view context, instead of '
                  code { 'ActionController.renderer.render' }
                  plain '. ~1.9× faster, ~half the allocations, byte-identical HTML.'
                end
                li do
                  plain 'view context / '
                  code { 'TagBuilder' }
                  plain ' — built once per thread per component class and reused. The context is '
                  plain 'request-bound ('
                  code { 'Phlex::Reactive.request_bound_view_context' }
                  plain ') so request-dependent helpers — '
                  code { 'form_authenticity_token' }
                  plain ', '
                  code { 'protect_against_forgery?' }
                  plain ', host-aware '
                  code { '*_url' }
                  plain ' — keep working during a re-render/broadcast. The request setup happens only on '
                  plain 'the build, not per render, and it is reset on Rails code reload.'
                end
                li do
                  code { 'reactive_token' }
                  plain ' — every render (it is in '
                  code { 'reactive_attrs' }
                  plain '). Ivar symbols ('
                  code { ':@count' }
                  plain ') and state string-keys are precomputed per class, so signing no longer allocates '
                  plain 'a Symbol/String per state key. The HMAC itself dominates and is unavoidable.'
                end
                li do
                  code { 'on(:action)' }
                  plain ' — every trigger rendered. The no-params case (the common one) skips re-serializing '
                  code { '{}' }
                  plain ' to JSON.'
                end
                li do
                  code { 'coerce_params' }
                  plain ' — every action with a param schema. The bracket-key regex is hoisted to a frozen '
                  plain 'constant (no per-key recompile).'
                end
                li do
                  plain 'client meta lookups — every dispatch. The page-stable action path is resolved once '
                  plain 'per controller; CSRF + pgbus connection id stay live (they can rotate).'
                end
              end
            end
          end
        end

        def measuring
          DocsUI::Section('Measuring') do
            DocsUI::Prose() do
              p { plain 'Everything is driven from rake:' }
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              rake bench           # the micro-benchmark suite (alias for bench:micro)
              rake bench:micro     # render, reactive_token, coerce_params — isolates each method
              rake bench:request   # end-to-end POST /reactive/actions through the full Rack stack
              rake bench:one[render]  # a single micro-bench by name
            SHELL
            DocsUI::Prose() do
              ul do
                li do
                  strong { 'Micro-benches' }
                  plain ' ('
                  code { 'benchmark/micro/*.rb' }
                  plain ') isolate one method with benchmark-ips (throughput) and memory_profiler '
                  plain '(allocations). They boot the dummy app so they exercise the real render path.'
                end
                li do
                  strong { 'The request bench' }
                  plain ' ('
                  code { 'benchmark/request/derailed.rb' }
                  plain ") drives the dummy app's full Rack stack (middleware → router → controller → token "
                  plain 'verify → action → re-render → turbo-stream) via '
                  code { 'Rack::MockRequest' }
                  plain ' — the same call-the-app primitive derailed_benchmarks uses — so the numbers '
                  plain 'reflect production action latency.'
                end
              end
              h3 { 'Reading the output' }
              p do
                plain 'benchmark-ips reports '
                strong { 'i/s' }
                plain ' (iterations per second — higher is better) and '
                strong { 'μs/i' }
                plain ' (microseconds per call — lower is better). memory_profiler reports '
                strong { 'objects/bytes allocated' }
                plain ' (transient GC pressure) and '
                strong { 'retained' }
                plain ' (objects that survive — a steady climb here is a leak). For a re-render, retained '
                plain 'should be 0; a non-zero retained count per render is the smell the view-context '
                plain 'memoization fixed.'
              end
            end
          end
        end

        def before_change
          DocsUI::Section('Measure BEFORE you change') do
            DocsUI::Prose() do
              p do
                plain 'The first rule: capture the baseline before touching code, or you cannot claim a '
                plain 'delta. The cleanest way for a gem is an isolated worktree so '
                code { 'main' }
                plain ' and your branch run the same script on the same machine:'
              end
            end
            DocsUI::Code(<<~SHELL, lexer: :shell)
              git worktree add --detach /tmp/baseline main
              # Copy the harness AND the Rakefile/Gemfile so `rake bench` exists in the
              # pristine tree (main predates the bench task).
              cp -r benchmark /tmp/baseline/ && cp Gemfile Rakefile /tmp/baseline/
              (cd /tmp/baseline && bundle install && RAILS_ENV=test bundle exec rake bench:micro) > /tmp/before.txt
              RAILS_ENV=test bundle exec rake bench:micro > /tmp/after.txt   # your branch
              diff /tmp/before.txt /tmp/after.txt
              git worktree remove --force /tmp/baseline
            SHELL
            DocsUI::Prose() do
              p do
                plain 'If the branch added a bench that calls a method not on '
                code { 'main' }
                plain ' (e.g. a new '
                code { 'reset_*!' }
                plain '), write a baseline-safe script that only calls methods present on '
                code { 'main' }
                plain ' and run that in both trees.'
              end
            end
            DocsUI::Callout(:note) do
              plain 'There is no committed baseline file — shared CI runners are too noisy for a hard ' \
                    'regression gate — which is exactly why the before/after has to be a deliberate ' \
                    'same-machine measurement, not a comparison against a number from another box.'
            end
            DocsUI::Prose() do
              p do
                plain 'Toggling a single optimization in place (e.g. '
                code { 'PHLEX_REACTIVE_NO_CACHE=1 ruby benchmark/micro/render.rb' }
                plain ') is an even cleaner apples-to-apples for one change — it removes machine-to-machine '
                plain 'and worktree variance.'
              end
            end
          end
        end

        def numbers
          DocsUI::Section('Representative numbers') do
            DocsUI::Prose() do
              p do
                plain 'Measured on Ruby 3.4 +YJIT, Apple Silicon, the dummy app — the before column is '
                plain 'pristine '
                code { 'main' }
                plain ' run in an isolated worktree with the same script as the after column, so it is a '
                plain 'true same-machine before/after. '
                strong { 'Your absolute numbers will differ; the ratios are the point.' }
              end
              ul do
                li do
                  code { 'render_component' }
                  plain ' throughput: 6.99k i/s (143 μs) → 14.1k i/s (71 μs) — '
                  strong { '2.0× faster' }
                  plain '.'
                end
                li do
                  code { 'render_component' }
                  plain ' allocations: 212 obj → 99 obj — '
                  strong { '−53%' }
                  plain '.'
                end
                li do
                  code { 'to_stream_replace' }
                  plain ' throughput: 4.60k i/s (217 μs) → 8.00k i/s (125 μs) — '
                  strong { '1.7× faster' }
                  plain '.'
                end
                li do
                  code { 'to_stream_replace' }
                  plain ' allocations: 331 obj → 191 obj — '
                  strong { '−42%' }
                  plain '.'
                end
                li do
                  code { 'reactive_token' }
                  plain ' (state) allocations: 14 obj → 11 obj — −21%.'
                end
                li do
                  code { 'on(:action)' }
                  plain ' (no params) allocations: 6 obj → 5 obj — −17%.'
                end
              end
              h3 { 'Full-stack request numbers' }
              p { plain 'No clean before/after — these are reference figures for production action shape:' }
              ul do
                li do
                  code { 'POST /reactive/actions' }
                  plain ' (state-backed): ~1.6k req/s (636 μs), 828 obj/req.'
                end
                li do
                  code { 'POST /reactive/actions' }
                  plain ' (record-backed, +DB): ~1.1k req/s (895 μs), 1316 obj/req.'
                end
                li do
                  code { 'coerce_params' }
                  plain ' (2-row nested form): ~37k i/s (27 μs), 218 obj/call.'
                end
              end
              h3 { 'What these tell you' }
              ul do
                li do
                  plain 'The render path got ~2× faster and halved its allocations — but at the full request '
                  plain 'level that delta is within noise, because routing + middleware + token verify + '
                  plain 'transaction dominate. Do not expect a render optimization to move request '
                  plain 'throughput; expect it to move broadcast-heavy code — one render per broadcast '
                  plain 'call, so K stream keys (or per-viewer rendering) = K renders with no HTTP — and '
                  plain 'to cut GC pressure under load.'
                end
                li do
                  plain 'Record-backed actions are ~1.4× slower than state-backed — that is the GlobalID '
                  plain 're-find + DB write, which is the security model working as designed (state lives in '
                  plain 'the database), not overhead to remove.'
                end
              end
            end
          end
        end

        def ci
          DocsUI::Section('CI') do
            DocsUI::Prose() do
              p do
                plain 'The '
                code { 'bench' }
                plain ' job in '
                code { '.github/workflows/main.yml' }
                plain ' runs the micro suite and the request bench on every PR and uploads the report as '
                plain 'the '
                code { 'benchmarks' }
                plain ' artifact. It is run-and-report, never a hard fail — it surfaces trends, it does not '
                plain "gate merges on a flaky threshold. Download the artifact from the PR's checks tab to "
                plain 'see the numbers for that branch.'
              end
            end
          end
        end

        def every_change
          DocsUI::Section('Performance is part of every change') do
            DocsUI::Prose() do
              p do
                plain 'See '
                a(href: 'https://github.com/mhenrixon/phlex-reactive/blob/main/.claude/rules/performance.md') do
                  plain '.claude/rules/performance.md'
                end
                plain ': any change to a hot path ships with a bench, the README/CHANGELOG/docs are updated, '
                plain 'and the JS vendored copy is re-synced. Run '
                code { '/perf' }
                plain ' to benchmark the current branch and get a written before/after.'
              end
            end
          end
        end

        def adding_a_benchmark
          DocsUI::Section('Adding a benchmark') do
            DocsUI::Prose() do
              p do
                plain 'A new hot path gets a new '
                code { 'benchmark/micro/<name>.rb' }
                plain '. Use the shared harness:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'benchmark/micro/my_hot_path.rb')
              require_relative "../support/boot"   # boots the dummy app + schema

              BenchSupport.header("my hot path")
              BenchSupport.ips { |x| x.report("thing") { thing_under_test } }
              BenchSupport.allocations("thing") { thing_under_test }
            RUBY
            DocsUI::Prose() do
              p do
                code { 'rake bench:micro' }
                plain ' picks it up automatically (it globs '
                code { 'benchmark/micro/*.rb' }
                plain ').'
              end
            end
          end
        end
      end
    end
  end
end
