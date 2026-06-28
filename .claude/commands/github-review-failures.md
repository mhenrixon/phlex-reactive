---
description: "Use when CI checks are failing on a PR — fetches failure logs, diagnoses root causes, implements fixes, and pushes until CI is green."
argument-hint: "PR number (e.g., 41 or #41)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(bundle exec:*), Read, Write, Edit, Glob, Grep, Agent
---

# Fix GitHub CI Failures: $ARGUMENTS

You are diagnosing and fixing CI failures on a GitHub pull request. Work systematically: identify failures, read logs, diagnose root causes, fix locally, verify, push.

## Phase 0: Determine the PR Number

The user may provide a PR number as `$ARGUMENTS`. Parse it flexibly:

- `PR41`, `PR 41`, `pr41` -> PR 41
- `41` -> PR 41
- `#41` -> PR 41
- Empty/blank -> auto-detect from current branch

**If no PR number is provided**, detect it automatically:

```bash
gh pr list --author=@me --head="$(git branch --show-current)" --state=open --json number,title
```

If exactly one open PR exists for the current branch, use it. If none or multiple, ask the user.

Once you have the PR number, confirm it:

```bash
gh pr view <PR_NUMBER> --json title,state,url
```

---

## Phase 1: Identify Failing Checks

```bash
gh pr checks <PR_NUMBER>
```

Categorise each failing check:

| Check Type | Examples | How to Get Logs |
|------------|----------|----------------|
| Lint (standardrb) + gem build | `Lint` | `gh run view <RUN_ID> --job=<JOB_ID> --log-failed` |
| Unit + request specs | `Ruby 3.2` / `3.3` / `3.4` | `gh run view <RUN_ID> --job=<JOB_ID> --log-failed` |
| Browser system specs (Playwright) | `System (browser)` | `gh run view <RUN_ID> --job=<JOB_ID> --log-failed` |

Extract the run ID and job IDs from the check URLs. The URL format is:
`https://github.com/mhenrixon/phlex-reactive/actions/runs/<RUN_ID>/job/<JOB_ID>`

If all checks pass or are pending, report that and stop.

---

## Phase 2: Fetch Failure Logs

For each failing check, get the logs:

```bash
# Get the failed job logs (condensed output)
gh run view <RUN_ID> --job=<JOB_ID> --log-failed
```

If `--log-failed` output is too large or unclear, try:

```bash
# Full log for a specific job
gh run view <RUN_ID> --job=<JOB_ID> --log 2>&1 | tail -100
```

---

## Phase 3: Diagnose Each Failure

For each failure, determine the root cause:

### Lint Failures

Look for:
- Standard offenses: file path, line number, cop name, message

**Key**: Standard failures can often be auto-fixed with `bundle exec standardrb --fix <file>`.

### Spec Failures

Look for:
- Test name and file path
- Error class and message
- Relevant backtrace lines (ignore framework noise)
- Whether it's a test environment issue vs actual code bug

**Key patterns**:
- `NameError: uninitialized constant` -> missing require or renamed class
- `NoMethodError: undefined method` -> API change, missing method
- `ActiveRecord::StatementInvalid` -> migration issue, missing column
- `expected: X, got: Y` -> logic bug or test needs updating

### Build Failures

Look for:
- Gem build errors: missing files in gemspec, syntax errors
- Bundle install failures: dependency conflicts

---

## Phase 4: Fix Locally

For each diagnosed failure:

1. **Read the relevant file** to understand context before fixing
2. **Make the fix** -- edit the file
3. **Verify locally** before committing:

```bash
# For standardrb failures
bundle exec standardrb <changed_files>

# For spec failures
bundle exec rspec <failing_spec_files>

# For full validation
bundle exec rake
```

### Fix Priority Order

1. **Lint/style fixes** first (fast, deterministic)
2. **Spec failures** second (may require understanding the code change)
3. **Build issues** third (usually gemspec or dependency)

---

## Phase 5: Commit and Push

```bash
git add <specific_files>
git commit -m "$(cat <<'EOF'
fix(ci): <brief description of what was fixed>

- Fix 1 description
- Fix 2 description
EOF
)"
git push
```

---

## Phase 6: Verify

After pushing, check if CI has been re-triggered:

```bash
gh pr checks <PR_NUMBER>
```

If there are still pending checks, report which checks are running and what was fixed. Do NOT poll in a loop -- report the status and let the user know.

If you can identify that certain failures will persist for environmental reasons (e.g., a pgbus-dependent spec that needs PostgreSQL, or a system spec where Playwright browsers failed to install), flag that explicitly.

---

## Important Notes

- **Read before fixing** -- always read the actual failing code before attempting a fix
- **Fix the root cause** -- don't add `# standard:disable` to bypass lint; fix the actual issue (a targeted `# rubocop:disable` is acceptable only when Standard is demonstrably wrong, e.g. `save_screenshot` flagged as a debugger)
- **Don't fix unrelated failures** -- if a spec was already failing on main, note it but don't fix it in this PR
- **CI environment differences** -- system specs run Playwright (cached browsers) under a server matrix: Puma (default) AND Falcon (`CAPYBARA_SERVER=falcon`). A failure on only one server is a transport-specific bug, not flakiness. pgbus-dependent specs run only on Ruby >= 3.3 (pgbus's floor) and need PostgreSQL; on 3.2 they are skipped by design.
- **Flaky tests** -- if a test passes locally but fails in CI, note it as potentially flaky rather than adding workarounds. Browser specs that assert a value right after a click (racing the morph) are a common false-flake — fix them to use a waiting matcher.
- **Don't retry CI blindly** -- diagnose first, fix, then push. Each push triggers a full CI run.

Now begin by determining the PR number and fetching the failing checks.
