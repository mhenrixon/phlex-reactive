# frozen_string_literal: true

# reactive_nested_remove(confirm:) with a %{field} PLACEHOLDER on a JSON-mode
# draft list (issue #222). A row added client-side via reactive_nested_add is a
# cloneNode of the <template>, so it carries the TEMPLATE's confirm string
# verbatim — the value-less "%{quantity}" placeholder. Before #222 that froze
# the message to the template string on every added row; now the client
# interpolates %{field} from the row's LIVE field values at click time, so the
# per-row confirm reflects the quantity the user actually typed into THAT row.
#
# Reconciled through the SAME /orders_json endpoint as DraftOrderJsonFormComponent
# and DraftOrderConfirmRemoveComponent, so the interpolation is the only thing
# under test.
class DraftOrderConfirmInterpolateComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  reactive_scope :order

  def view_template
    div(**mix(
      reactive_root(id: "draft_order_confirm_interpolate_form", data: { testid: "draft-order-interp" })
    )) do
      form(action: "/orders_json", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        input(type: "hidden", **reactive_field(:line_items), value: "[]", data: { testid: "json-field" })

        div(**mix(reactive_nested_list(:line_items, as: :json), data: { testid: "items" }))
        row_template
        button(**mix(reactive_nested_add(:line_items), data: { testid: "add-item" })) { "Add item" }

        button(type: "submit", data: { testid: "create-order" }) { "Create order" }
      end
    end
  end

  private

  def row_template
    template(**reactive_nested_template(:line_items)) { row_fields }
  end

  def row_fields
    div(**mix(reactive_nested_row, data: { testid: "item-row" })) do
      input(name: nested_field_name(:line_items, :quantity), type: "number", data: { testid: "qty" })
      input(name: nested_field_name(:line_items, :price), type: "number", data: { testid: "price" })
      # A %{field} PLACEHOLDER, not a per-row string. The template row is
      # value-less, so this renders the literal "%{quantity}"; the client
      # interpolates it from the added row's own quantity field on remove. The
      # %{quantity} is a CLIENT interpolation template (the reactive runtime
      # parses it), not a Ruby format string — so Style/FormatStringToken's
      # annotated-token preference doesn't apply here.
      # rubocop:disable-next Style/FormatStringToken
      button(**mix(reactive_nested_remove(confirm: "Remove line item with quantity %{quantity}?"),
        data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
