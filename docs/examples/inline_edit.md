---
layout: default
title: Inline edit
parent: Examples
nav_order: 4
---

# Example: inline edit (show ↔ edit)

The classic "click to edit a field in place" pattern. In plain Hotwire this is a
Stimulus controller plus three routes (`inline_edit`, `inline_update`,
`inline_cancel`) and partials. Here it's one component with two actions.

```ruby
class Fields::InlineEdit < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :record
  reactive_state :attribute, :editing     # which field, and the mode

  action :edit
  action :cancel
  action :save, params: { value: :string }

  def initialize(record:, attribute:, editing: false)
    @record = record
    @attribute = attribute.to_sym
    @editing = editing
  end

  def id = dom_id(@record, "inline_#{@attribute}")

  def edit   = @editing = true
  def cancel = @editing = false

  def save(value:)
    authorize! @record, :update?
    @record.update!(@attribute => value)
    @editing = false
  end

  def view_template
    span(id:, **reactive_attrs) do
      if @editing
        input(name: "value", value: current_value, autocomplete: "off")
        button(**on(:save)) { "Save" }
        button(**on(:cancel)) { "Cancel" }
      else
        span(**on(:edit), class: "editable") { current_value.presence || "—" }
      end
    end
  end

  private

  def current_value = @record.public_send(@attribute)
end
```

Render it for any field:

```ruby
render Fields::InlineEdit.new(record: @user, attribute: :name)
render Fields::InlineEdit.new(record: @user, attribute: :email)
```

## Notes

- **Two pieces of identity**: `reactive_record :record` (the row, re-found via
  GlobalID) and `reactive_state :attribute, :editing` (which field, what mode).
  Both are signed; the client can't switch `@attribute` to a column it shouldn't
  edit because the value is signed into the token.
- **Mode is server state.** `edit`/`cancel`/`save` flip `@editing` and re-render
  the same element — no separate "edit" route or partial.
- **Authorize on save.** `edit`/`cancel` are harmless view toggles; `save`
  mutates, so it authorizes.
- **The `span(**on(:edit))`** turns the display text into the click target. Add
  `tabindex` / keyboard handling if you need a11y on non-button triggers.
- **Rich-text fields work too.** A named `lexxy-editor`, `trix-editor`, or
  `[contenteditable]` is auto-collected on submit alongside plain inputs — so
  `save` receives its value, not a blank. See
  [what gets auto-collected](../architecture.md#what-collected-fields-are).

## Want it to update other viewers too?

Broadcast on save:

```ruby
def save(value:)
  authorize! @record, :update?
  @record.update!(@attribute => value)
  @editing = false
  Fields::InlineEdit.broadcast_replace_to(
    @record, model: @record, attribute: @attribute
  )
end
```

Now everyone viewing that record sees the new value land in place.
