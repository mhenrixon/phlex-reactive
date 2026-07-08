# frozen_string_literal: true

# Fill-then-add + JSON mode (issue #208 Scenarios A + B together). The add
# controls live OUTSIDE the row (fill-then-add) AND the list serializes to ONE
# hidden JSON field (as: :json). Clicking "Add" snapshots the sources into a
# new row, clears them, and the client re-serializes every surviving row into
# order[line_items] — the app's hand-rolled JSON.parse controller reconciles.
class DraftOrderFillJsonFormComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  reactive_scope :order

  def view_template
    div(**mix(reactive_root(id: "draft_order_fill_json_form", data: { testid: "draft-order-fill-json" }))) do
      form(action: "/orders_json", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        label { "Quantity" }
        input(id: "src-qty", type: "number", data: { testid: "src-qty" })
        label { "Price" }
        input(id: "src-price", type: "number", data: { testid: "src-price" })

        input(type: "hidden", **reactive_field(:line_items), value: "[]", data: { testid: "json-field" })

        div(**mix(reactive_nested_list(:line_items, as: :json), data: { testid: "items" }))
        row_template
        button(**mix(
          reactive_nested_add(:line_items,
            from: { quantity: "#src-qty", price: "#src-price" },
            clear: true),
          data: { testid: "add-item" }
        )) { "Add item" }

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
      button(**mix(reactive_nested_remove, data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
