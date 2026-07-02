---
model: opus
description: "Use when implementing any feature or fixing any bug — enforces RED-GREEN-REFACTOR: write failing test first, implement minimum code to pass, then refactor."
---

# TDD Command

Enforce test-driven development with RED → GREEN → REFACTOR.

## The TDD Cycle

```text
RED:      Write a failing test (it MUST fail first)
GREEN:    Write MINIMAL code to pass (nothing more)
REFACTOR: Improve code while keeping tests green
REPEAT:   Next scenario
```

## When to Use

- Implementing a new reactive feature (a new `action`, a Streamable method)
- Adopting a pgbus primitive (exclude:, typed events, coalescing, presence)
- Fixing a bug (write the reproducing test FIRST)
- Changing the client runtime, the endpoint, or the mixins

## Workflow

### Step 1: Write Failing Tests (RED)

Pick the cheapest layer that proves the behavior:

```ruby
# Unit (no Rails): the DSL / identity / capability gate
RSpec.describe Phlex::Reactive::Component do
  it "registers a declared action" do
    expect(klass.reactive_action?(:increment)).to be(true)
  end
end

# Request: the endpoint
RSpec.describe "Reactive actions", type: :request do
  it "forbids an undeclared action" do
    post_action(CounterComponent, payload: {...}, act: "drop_table")
    expect(response).to have_http_status(:forbidden)
  end
end

# Broadcast: the server→client half
it "broadcasts an append to the room stream" do
  expect { send_message(...) }.to broadcast_an_append_to(stream)
end

# System: the real browser loop
it "increments without a full page reload" do
  visit "/counter"; find("[data-testid=inc]").click
  expect(page).to have_css("[data-testid=count]", text: "1")
end
```

### Step 2: Run — Verify FAIL

```bash
bundle exec rspec <spec_file>
# FAIL — confirms the test runs, tests the right thing, and the code doesn't already exist
```

### Step 3: Implement Minimal Code (GREEN)

### Step 4: Run — Verify PASS

```bash
bundle exec rspec <spec_file>
# N examples, 0 failures
```

### Step 5: Refactor

Improve while staying green: extract methods, improve names, reduce duplication.

### Step 6: Run Full Suite + Lint

```bash
bundle exec rspec spec/phlex spec/requests
bundle exec rubocop
```

## Coverage Expectations

| Code | Minimum |
|------|---------|
| All code | 80% |
| identity sign/verify (tamper, wrong key, wrong purpose) | 100% |
| the action endpoint (default-deny, schema coercion, 403/404/400) | 100% |
| the capability gate (pgbus absent / too old / present) | 100% |

## pgbus features: test BOTH paths

Any feature using a pgbus primitive MUST have specs for:
- **pgbus present** — the primitive is called with the right args
- **pgbus absent / too old** — the fallback path runs, no `ArgumentError` leaks
  (use a "0.9.1-shaped" `broadcast` double without `:exclude` as the gate's regression guard)

## Best Practices

**DO:** test FIRST; verify RED; minimal GREEN; refactor green; drive browser specs
by `data-testid` with waiting matchers; mock the verifier in unit specs.

**DON'T:** implement before testing; assert a snapshot value right after a click
(race the morph); test implementation details; skip the pgbus-absent path.

## Checklist

- [ ] Tests written BEFORE implementation; RED verified
- [ ] Minimal GREEN; refactored green
- [ ] Coverage meets the bar (100% on security + the gate)
- [ ] Edge + error paths covered
- [ ] pgbus-present AND pgbus-absent both tested
- [ ] `bundle exec rubocop` passes
