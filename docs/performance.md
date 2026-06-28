---
layout: default
title: Performance
nav_order: 8
---

# Performance

phlex-reactive aims to be fast in the places that run on every interaction: the
component re-render, the identity-token signing, the param coercion, and the
client request hot path. This page documents how those paths are kept fast, how
to measure them yourself, and how performance is part of every change.

The honest summary: **the re-render is the part we control and the part we
optimized hardest, but a full HTTP action is dominated by the Rails middleware
stack and (for record-backed components) the database** — so the render wins
matter most for broadcasts (one change fanned out to N subscribers = N renders
with no HTTP overhead to amortize against). Measure before you optimize; the
harness below exists so you never have to guess.

## The hot paths

| Path | When it runs | What we did |
|------|--------------|-------------|
| `render_component` | every action re-render **and every broadcast render** | Renders through phlex-rails' lightweight `#render_in` against a **memoized** off-request view context, instead of `ActionController.renderer.render`. ~1.9× faster, ~half the allocations, byte-identical HTML. |
| view context / `TagBuilder` | every render + broadcast | Built **once per component class** and reused (the comment used to say "memoized" — now it actually is). Reset on Rails code reload so a reloaded controller is never served stale. |
| `reactive_token` | every render (it's in `reactive_attrs`) | Ivar symbols (`:@count`) and state string-keys are precomputed per class, so signing no longer allocates a `Symbol`/`String` per state key. The HMAC itself dominates and is unavoidable. |
| `on(:action)` | every trigger rendered | The no-params case (the common one) skips re-serializing `{}` to JSON. |
| `coerce_params` | every action with a param schema | The bracket-key regex is hoisted to a frozen constant (no per-key recompile). |
| client meta lookups | every dispatch | The page-stable action path is resolved once per controller; CSRF + pgbus connection id stay live (they can rotate). |

## Measuring

Everything is driven from `rake`:

```bash
rake bench           # the micro-benchmark suite (alias for bench:micro)
rake bench:micro     # render, reactive_token, coerce_params — isolates each method
rake bench:request   # end-to-end POST /reactive/actions through the full Rack stack
rake bench:one[render]  # a single micro-bench by name
```

- **Micro-benches** (`benchmark/micro/*.rb`) isolate one method with
  [`benchmark-ips`](https://github.com/evanphx/benchmark-ips) (throughput) and
  [`memory_profiler`](https://github.com/SamSaffron/memory_profiler)
  (allocations). They boot the dummy app so they exercise the real render path.
- **The request bench** (`benchmark/request/derailed.rb`) drives the dummy app's
  full Rack stack (middleware → router → controller → token verify → action →
  re-render → turbo-stream) via `Rack::MockRequest` — the same call-the-app
  primitive [`derailed_benchmarks`](https://github.com/zombocom/derailed_benchmarks)
  uses — so the numbers reflect production action latency. `derailed_benchmarks`
  is loaded for its memory/object helpers when you want a deeper dive.

### Reading the output

`benchmark-ips` reports **i/s** (iterations per second — higher is better) and
**μs/i** (microseconds per call — lower is better). `memory_profiler` reports
**objects/bytes allocated** (transient GC pressure) and **retained** (objects
that survive — a steady climb here is a leak). For a re-render, *retained should
be 0*; a non-zero retained count per render is the smell the view-context
memoization fixed.

### Measure BEFORE you change

The first rule: capture the baseline **before** touching code, or you can't
claim a delta. The cleanest way for a gem is an isolated worktree so `main` and
your branch run the *same script* on the *same machine*:

```bash
git worktree add --detach /tmp/baseline main
# Copy the harness AND the Rakefile/Gemfile so `rake bench` exists in the
# pristine tree (main predates the bench task).
cp -r benchmark /tmp/baseline/ && cp Gemfile Rakefile /tmp/baseline/
(cd /tmp/baseline && bundle install && RAILS_ENV=test bundle exec rake bench:micro) > /tmp/before.txt
RAILS_ENV=test bundle exec rake bench:micro > /tmp/after.txt   # your branch
diff /tmp/before.txt /tmp/after.txt
git worktree remove --force /tmp/baseline
```

If the branch added a bench that calls a method not on `main` (e.g. a new
`reset_*!`), write a baseline-safe script that only calls methods present on
`main` and run *that* in both trees — exactly how this PR's render numbers were
taken.

There is no committed baseline file (shared CI runners are too noisy for a hard
regression gate), which is exactly why the before/after has to be a deliberate
same-machine measurement, not a comparison against a number from another box.

Toggling a single optimization in place (e.g. `PHLEX_REACTIVE_NO_CACHE=1 ruby
benchmark/micro/render.rb`) is an even cleaner apples-to-apples for one change —
it removes machine-to-machine *and* worktree variance.

## Representative numbers

Measured on Ruby 3.4 +YJIT, Apple Silicon, the dummy app — the **before** column
is pristine `main` run in an isolated `git worktree` with the *same script* as
the **after** column, so it's a true same-machine before/after. **Your absolute
numbers will differ; the ratios are the point.**

| Benchmark | Before | After | Delta |
|-----------|--------|-------|-------|
| `render_component` throughput | 6.99k i/s (143 μs) | 14.1k i/s (71 μs) | **2.0× faster** |
| `render_component` allocations | 212 obj | 99 obj | **−53%** |
| `to_stream_replace` throughput | 4.60k i/s (217 μs) | 8.00k i/s (125 μs) | **1.7× faster** |
| `to_stream_replace` allocations | 331 obj | 191 obj | **−42%** |
| `reactive_token` (state) allocations | 14 obj | 11 obj | −21% |
| `on(:action)` (no params) allocations | 6 obj | 5 obj | −17% |

Full-stack request numbers (no clean before/after — see below):

| Benchmark | Throughput | Allocations |
|-----------|-----------|-------------|
| `POST /reactive/actions` (state-backed) | ~1.6k req/s (636 μs) | 828 obj/req |
| `POST /reactive/actions` (record-backed, +DB) | ~1.1k req/s (895 μs) | 1316 obj/req |
| `coerce_params` (2-row nested form) | ~37k i/s (27 μs) | 218 obj/call |

What these tell you:

- The render path got ~2× faster and halved its allocations — **but at the full
  request level that delta is within noise**, because routing + middleware +
  token verify + transaction dominate. Don't expect a render optimization to
  move request throughput; expect it to move **broadcast fan-out** (N renders,
  no HTTP) and to cut GC pressure under load.
- Record-backed actions are ~1.4× slower than state-backed — that's the GlobalID
  re-find + DB write, which is the security model working as designed (state
  lives in the database), not overhead to remove.

## CI

The `bench` job in `.github/workflows/main.yml` runs the micro suite and the
request bench on every PR and **uploads the report as the `benchmarks`
artifact**. It is **run-and-report, never a hard fail** — it surfaces trends, it
does not gate merges on a flaky threshold. Download the artifact from the PR's
checks tab to see the numbers for that branch.

## Performance is part of every change

See [`.claude/rules/performance.md`](https://github.com/mhenrixon/phlex-reactive/blob/main/.claude/rules/performance.md):
any change to a hot path ships with a bench, the README/CHANGELOG/docs are
updated, and the JS vendored copy is re-synced. Run `/perf` to benchmark the
current branch and get a written before/after.

## Adding a benchmark

A new hot path gets a new `benchmark/micro/<name>.rb`. Use the shared harness:

```ruby
require_relative "../support/boot"   # boots the dummy app + schema

BenchSupport.header("my hot path")
BenchSupport.ips { |x| x.report("thing") { thing_under_test } }
BenchSupport.allocations("thing") { thing_under_test }
```

`rake bench:micro` picks it up automatically (it globs `benchmark/micro/*.rb`).
