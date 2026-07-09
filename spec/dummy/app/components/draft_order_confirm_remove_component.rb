# frozen_string_literal: true

# reactive_nested_remove(confirm:) on a JSON-mode draft list (issue #218).
# Removing a row can be a real loss (line items with entered amounts), so the
# remove trigger gates behind the SAME overridable confirmResolver the other
# triggers use — no bespoke JS. The message is per-row: the app renders a
# different string per row at render time, exactly as it does for
# on(:destroy, confirm:). Reconciled through the SAME /orders_json endpoint as
# DraftOrderJsonFormComponent, so the confirm is the only thing under test.
class DraftOrderConfirmRemoveComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  reactive_scope :order

  def view_template
    div(**mix(
      reactive_root(id: "draft_order_confirm_remove_form", data: { testid: "draft-order-confirm" })
    )) do
      form(action: "/orders_json", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        label { "Total" }
        input(**reactive_field(:total, type: "number", value: "0", data: { testid: "total" }))

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

  def row_fields(index: nil)
    kwargs = index.nil? ? {} : { index: }
    div(**mix(reactive_nested_row, data: { testid: "item-row" })) do
      input(name: nested_field_name(:line_items, :quantity, **kwargs), type: "number", data: { testid: "qty" })
      input(name: nested_field_name(:line_items, :price, **kwargs), type: "number", data: { testid: "price" })
      # The per-row confirm string is built at render time — no gem-side
      # interpolation feature needed, just a different message per row.
      button(**mix(reactive_nested_remove(confirm: "Really remove this line item?"),
        data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
