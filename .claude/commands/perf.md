---
description: "Benchmark the current branch against main and report a same-machine before/after. Use when a change touches a hot path (render, token signing, param coercion, broadcast, client dispatch) or when asked to measure performance."
argument-hint: "optional: a specific hot path or bench name (e.g. render)"
---

# Performance Command

Measure, don't guess. This command produces a **same-machine before/after** so
any performance claim is backed by numbers, and keeps the perf docs/discipline
in sync. See the performance page (`docs/app/views/docs/pages/performance.rb`) for the hot paths and how the harness works.

## The non-negotiable rule

**Measure BEFORE you change.** A delta you didn't baseline is not a delta. If a
change already landed without a baseline, reconstruct one from `main` in a
worktree (below) — never report a number against a baseline from another machine
or another day.

## Workflow

### 1. Baseline `main` (before)

Capture pristine `main` with the SAME bench script you'll run on the branch, in
an isolated worktree (so `lib/`+`app/` are pristine but the harness is present):

```bash
git worktree add --detach /tmp/pr-baseline main
# Copy the harness AND Rakefile/Gemfile — main predates the bench task.
cp -r benchmark /tmp/pr-baseline/ && cp Gemfile Rakefile /tmp/pr-baseline/
(cd /tmp/pr-baseline && bundle install && RAILS_ENV=test bundle exec rake bench:micro) > /tmp/before.txt
```

If the branch added a bench method that doesn't exist on `main` (e.g. a new
`reset_*!`), write a baseline-safe script that only calls methods present on
`main`, and run that script in BOTH trees.

### 2. Measure the branch (after)

```bash
RAILS_ENV=test rake bench:micro > /tmp/after.txt
RAILS_ENV=test rake bench:request   # end-to-end, for the request-cycle picture
diff /tmp/before.txt /tmp/after.txt
git worktree remove --force /tmp/pr-baseline
```

For a single isolated change, prefer the in-place toggle (e.g.
`PHLEX_REACTIVE_NO_CACHE=1 ruby benchmark/micro/render.rb`) — it removes
worktree variance entirely.

### 3. Report HONESTLY

- Give throughput (i/s, μs/i) AND allocations (obj/call, retained). Retained > 0
  per render is a leak — call it out.
- **Distinguish a method-level win from a request-level win.** A 2× faster
  render barely moves full-request throughput (Rails middleware + DB dominate)
  but is a 2× win on the broadcast fan-out path. Say which.
- If a number is within run-to-run noise (`benchmark-ips` shows ±%), say "within
  noise" — don't dress it up.
- If you only measured *after* (no clean baseline), say so explicitly.

### 4. Keep perf continuous (every PR that touches a hot path)

- [ ] A bench exists for the changed hot path (`benchmark/micro/<name>.rb` or
      the request bench). Add one if missing — `rake bench:micro` globs them.
- [ ] The before/after numbers are in the PR body.
- [ ] The performance page (`docs/app/views/docs/pages/performance.rb`) updated if the representative numbers moved.
- [ ] CHANGELOG notes the perf change (`perf:` scope).
- [ ] If the client (`reactive_controller.js`) changed, the vendored copy
      (`spec/dummy/public/vendor/reactive_controller.js`) is re-synced and the
      JS tests pass.

## The hot paths to watch

| Path | Bench | Note |
|------|-------|------|
| `render_component` / `to_stream_replace` | `benchmark/micro/render.rb` | The biggest lever; dominates broadcast fan-out. |
| `reactive_token` | `benchmark/micro/token.rb` | Runs every render; HMAC dominates, assembly is what we trim. |
| `coerce_params` | `benchmark/micro/coerce_params.rb` | Per action with a schema; recursion allocations. |
| full request | `benchmark/request/derailed.rb` | The production latency picture. |

Argument (`$ARGUMENTS`): if a specific path/bench is named, focus the
measurement there with `rake bench:one[<name>]`; otherwise run the full suite.
