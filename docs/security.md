---
layout: default
title: Security
nav_order: 4
---

# Security & threat model

Every reactive action is a browser-reachable RPC. phlex-reactive makes the safe
path the default, but you own the authorization boundary. Read this once.

## What the signature guarantees (and what it doesn't)

The DOM token is a `MessageVerifier`-signed payload:

- Record-backed: `{ "c" => "Todos::Item", "gid" => "gid://app/Todo/42" }`
- State-backed: `{ "c" => "Counter", "s" => { "count" => 3 } }`

**Guarantees** (tampering any of these fails verification → HTTP 400):

- The component class can't be swapped (can't point a `Todo` token at an
  `AdminUser` component).
- The record's GlobalID can't be swapped or forged.
- State-backed values can't be edited.

**Does NOT guarantee**: that *this user* may act on this record. The signature
proves the token is one **we** minted, not that the current session is allowed to
mutate the target. **You must authorize.**

## The four rules

### 1. Authorize inside every mutating action

```ruby
def rename(title:)
  authorize! @todo, :update?      # Pundit / ActionPolicy / your check
  @todo.update!(title:)
end
```

Register your authorizer's exception so it renders as 403:

```ruby
# config/initializers/phlex_reactive.rb
Phlex::Reactive.authorization_errors = [Pundit::NotAuthorizedError]
# or [ActionPolicy::Unauthorized]
```

A useful discipline: **treat an action without an `authorize!` as a bug** unless
it's provably harmless (a view-mode toggle on already-visible data). Consider a
RuboCop rule or a code-review checklist for `action`-declared methods.

### 2. Actions are default-deny — keep it that way

Only methods declared with `action :name` are invokable. Don't declare an action
you don't intend to expose. Public methods without `action` are unreachable, but
don't rely on obscurity — declare narrowly.

### 3. Params are schema-coerced — declare them

```ruby
action :rename, params: { title: :string }
def rename(title:) = @todo.update!(title:)   # only `title`, cast to String
```

Anything not in the schema is dropped before reaching your method, so a malicious
`{ admin: true, title: "x" }` body can't mass-assign. Never do
`@record.update!(params)` — take explicit, declared params.

### 4. Don't put secrets in state-backed tokens

State-backed tokens are *signed* (tamper-proof) but **not encrypted** — the
values are readable in the DOM (base64). Don't sign secrets into `reactive_state`.
For anything sensitive, use `reactive_record` (only the GlobalID is exposed) and
read the sensitive data server-side.

## CSRF and authentication

The action endpoint inherits from `Phlex::Reactive.base_controller_name`
(default `ActionController::Base`). For a real app:

```ruby
Phlex::Reactive.base_controller_name = "ApplicationController"
```

This gives you CSRF protection (the client sends `X-CSRF-Token`) and your auth
filters. **Caveat**: if you have *public* reactive components (e.g. on a logged-
out page) and your `ApplicationController` force-redirects unauthenticated
requests to a login page, the action POST will be redirected and silently fail.
Either:

- `skip_before_action :authenticate` for the action endpoint (subclass it), or
- keep public components state-backed and authorize per-action where it matters.

## The endpoint's failure modes

| Situation | Response |
|---|---|
| Tampered/forged/expired token | `400 Bad Request` |
| Undeclared action | `403 Forbidden` |
| `authorize!` raised (registered error) | `403 Forbidden` |
| Record GlobalID no longer resolves | `404 Not Found` |
| Unknown / non-reactive component class | `400 Bad Request` |

The client runtime logs non-OK responses and applies no DOM change.

## Token lifetime & rotation

Tokens are signed with `secret_key_base` (or your `Phlex::Reactive.verifier`).
They don't expire by default. If you need expiry, set a verifier with an
`expires_in` policy, or include a server-checked timestamp in state. Rotating
`secret_key_base` invalidates all outstanding tokens (open tabs must reload).

## Quick checklist

- [ ] Every mutating action calls `authorize!` (or is provably harmless).
- [ ] `Phlex::Reactive.authorization_errors` includes your authorizer's error.
- [ ] Every action with input declares a `params:` schema.
- [ ] No `@record.update!(params)` — only declared params.
- [ ] No secrets in `reactive_state`; sensitive data uses `reactive_record`.
- [ ] `base_controller_name` set to `ApplicationController` (CSRF + auth).
- [ ] Public components don't get redirected to login on the action POST.
