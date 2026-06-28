# Coding Style Rules

## File Organization

**MANY SMALL FILES > FEW LARGE FILES**

- High cohesion, low coupling
- 200-400 lines typical
- 800 lines maximum per file
- Extract complex logic to dedicated classes
- Organize by concern (core/config, streamable, component, controller, client runtime)

## Ruby Style

Lint with **RuboCop** (`bundle exec rubocop`). RuboCop owns formatting —
don't hand-fight it; run `rubocop -A` and review.

### Classes & Methods

```ruby
# Good: small, focused methods
def create
  payload = verified_payload
  component = resolve_component(payload["c"]).from_identity(payload)
  run_action(component, action_def, coerced_params)
  render turbo_stream: component.to_stream_replace
end

# Bad: one giant method doing verification, dispatch, rendering, error handling
```

### The component self-targets

```ruby
# Good: the component owns its id; replace/broadcast target it automatically
render turbo_stream: TodoItem.replace(@todo)
TodoItem.broadcast_replace_to(@todo.list, :todos, model: @todo)

# Bad: hand-picking a Turbo target
render turbo_stream: turbo_stream.replace("todo_#{@todo.id}", partial: ...)
```

### Identity, never state

```ruby
# Good: sign identity; re-find the record server-side
reactive_record :todo                 # token carries todo.to_gid
def from_identity(payload) = new(todo: GlobalID::Locator.locate(payload["gid"]))

# Bad: ship state to the client and trust it back (mass-assignment surface)
```

### Authorize + declared params

```ruby
# Good
action :rename, params: { title: :string }
def rename(title:)
  authorize! @todo, :update?
  @todo.update!(title:)
end

# Bad: undeclared action, raw params, no authorization
def rename = @todo.update!(params)
```

### `#id` runs before render

```ruby
# Good: render-context-free
def id = dom_id(@todo)   # Streamable#dom_id -> ActionView::RecordIdentifier

# Bad: Phlex's render-time helper raises HelpersCalledBeforeRenderError here
```

### Combining attributes with `on(...)` / `reactive_attrs`

```ruby
# Good: mix deep-merges (data-action survives)
button(**mix(on(:increment), class: "btn", data: { testid: "inc" })) { "+" }

# Bad: the extra data: clobbers on()'s data:, so the action never binds
button(**on(:increment), data: { testid: "inc" }) { "+" }
```

### pgbus is optional — detect, don't depend

```ruby
# Good: capability gate, graceful fallback
if Phlex::Reactive.pgbus_streams?
  Pgbus.stream(Pgbus.stream_key!(key)).broadcast(tag, target:, exclude:)
else
  Turbo::StreamsChannel.broadcast_append_to(*streamables, target:, html: tag)
end

# Bad: assume pgbus, or call a pgbus-only keyword unguarded (ArgumentError on old pgbus)
```

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Methods are small (<30 lines ideal, <50 max)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Components self-target via `#id` — no hand-picked targets
- [ ] Mutating actions authorize; inputs declare a param schema
- [ ] pgbus features are capability-gated and degrade gracefully
- [ ] `bundle exec rubocop` passes
