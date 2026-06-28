# frozen_string_literal: true

# Issue #30: a spreadsheet-like line-item row. Two live fields (quantity, price)
# each fire a DEBOUNCED `update`. The action saves and re-streams ONLY the total
# cell via `reply.streams` — NOT a full-self replace. So when the user types a
# quantity, tabs to price, and keeps typing, the debounced save of the quantity
# field does NOT tear down the now-focused price input (which a full-self replace
# would). The signed token still rolls forward, via the tiny reactive:token
# stream the endpoint appends — so the next field's save still verifies.
class PartialGridComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :line_item

  action :update, params: { quantity: :integer, price: :integer }

  def initialize(line_item:)
    @line_item = line_item
  end

  def id = dom_id(@line_item)

  # The total cell's own DOM id — addressable as its own Turbo target so we can
  # re-stream JUST it, leaving the row's inputs untouched.
  def total_id = dom_id(@line_item, "total")

  # Persist the edit, then re-stream ONLY the total cell. reply.streams emits
  # exactly this one update + a token-only refresh — no full-row replace — so the
  # sibling field the user is mid-typing in survives.
  def update(quantity:, price:)
    @line_item.update!(quantity:, price:)
    reply.streams(total_stream)
  end

  def view_template
    div(id:, **reactive_attrs) do
      input(**mix(on(:update, event: "input", debounce: 100),
        name: "quantity", value: @line_item.quantity, data: { testid: "quantity" }))
      input(**mix(on(:update, event: "input", debounce: 100),
        name: "price", value: @line_item.price, data: { testid: "price" }))
      total_cell
    end
  end

  private

  # The companion total cell — rendered both on first paint (inside the row) and
  # re-streamed on its own by #total_stream after a save.
  def total_cell
    span(id: total_id, data: { testid: "total" }) { @line_item.total.to_s }
  end

  # A raw turbo-stream that updates only the total cell. Built off the same
  # render context the endpoint uses, so it carries no row token (the endpoint's
  # token-only stream handles the refresh).
  def total_stream
    self.class.turbo_stream_builder.update(total_id, html: @line_item.total.to_s)
  end
end
