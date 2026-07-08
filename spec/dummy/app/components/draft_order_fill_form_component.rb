# frozen_string_literal: true

# Fill-then-add draft rows (issue #208 Scenario A). Unlike the inline-edit
# DraftOrderFormComponent (type INTO the new row), the add controls live
# OUTSIDE the row: a preset <select> that carries a quantity + price, and an
# "Add" button that SNAPSHOTS those values into a new row via
# reactive_nested_add(from:), then clears the sources for the next entry. Zero
# JS, same accepts_nested_attributes_for wire — the seeded values ride the
# renumbered order[line_items_attributes][<index>][…] names on submit.
class DraftOrderFillFormComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  reactive_scope :order

  def view_template
    div(**mix(reactive_root(id: "draft_order_fill_form", data: { testid: "draft-order-fill" }))) do
      form(action: "/orders", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        # The add controls — OUTSIDE the row. Plain inputs the "Add" button snapshots.
        label { "Quantity" }
        input(id: "src-qty", type: "number", data: { testid: "src-qty" })
        label { "Price" }
        input(id: "src-price", type: "number", data: { testid: "src-price" })

        div(**mix(reactive_nested_list(:line_items), data: { testid: "items" }))
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

  # The template row's fields are hidden — the user never types into the row in
  # fill-then-add; the sources above do. (A visible row could show the values;
  # kept minimal here so the system spec asserts what got seeded.)
  def row_fields
    div(**mix(reactive_nested_row, data: { testid: "item-row" })) do
      input(name: nested_field_name(:line_items, :quantity), type: "number", data: { testid: "qty" })
      input(name: nested_field_name(:line_items, :price), type: "number", data: { testid: "price" })
      button(**mix(reactive_nested_remove, data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
