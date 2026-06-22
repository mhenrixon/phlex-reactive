---
layout: default
title: Testing
nav_order: 7
---

# Testing reactive components

Reactive components are plain Ruby objects with a few extra class methods, so
most testing is fast unit testing. Three layers, cheapest first.

## 1. Unit: actions are just methods

Build the component, call the action, assert the state changed. No HTTP, no
browser.

```ruby
test "toggle flips done" do
  todo = todos(:write_docs)         # done: false
  component = Todos::Item.new(todo:)
  component.toggle
  assert todo.reload.done?
end
```

## 2. Unit: the identity token round-trips

Verify the signed token rebuilds the same component (and that tampering fails).

```ruby
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
```

## 3. Integration: the action endpoint

POST a signed token to `/reactive/actions` and assert the turbo-stream response.
Mint the token the same way the component does.

```ruby
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
```

For authorization, stub the current user / policy and assert `:forbidden` when
the action's `authorize!` should deny.

## 4. System / browser: the full loop & broadcasts

Use a system test (Capybara) or a browser-automation CLI for the end-to-end loop
and cross-tab broadcasts. The key assertions:

- Clicking a trigger updates the component **without a full page reload** (assert
  a value set on `window` survives the interaction).
- A change in one session appears in another subscribed session.

```ruby
# system test sketch
test "counter increments without reload" do
  visit counter_path
  page.execute_script("window.__marker = 'alive'")
  click_button "+"
  assert_selector "#counter .value", text: "1"
  assert_equal "alive", page.evaluate_script("window.__marker")  # no reload
end
```

For cross-tab, open two sessions (two `Capybara::Session`s or two browser
contexts), act in one, and assert the morph appears in the other. Allow a beat
for the SSE round trip.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Click does nothing, count stays 0 | Controller lazy-loaded, clicked before connect | Register `reactive` **eagerly** ([installation](installation.md)) |
| Click reloads the whole page | Bare `<button>` defaulted to `type=submit` in a form | `on(:click)` already sets `type=button`; ensure you spread it |
| 403 from the endpoint | Undeclared action, or `authorize!` denied | Declare the `action`; check the policy |
| 400 from the endpoint | Token tampered, or `action` key collided | Use the `act` wire key (the gem does); don't rename it |
| Rapid clicks lose updates | (Shouldn't happen) stale-token race | The runtime queues + threads tokens; file a bug with a repro |
| Cross-tab not syncing | Subscriber/broadcaster stream keys differ | Pass the **same raw `*streamables`** to `turbo_stream_from` and `broadcast_*_to` |
| Action POST redirected to /sign_in | Auth filter on a public component | `skip_before_action :authenticate` on the endpoint, or keep it state-backed |
