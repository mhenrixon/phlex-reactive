# frozen_string_literal: true

# JSON-mode draft nested rows (issue #208). Same primitive as
# DraftOrderFormComponent, but the list opts into `as: :json`: instead of
# posting Rails accepts_nested_attributes_for names, the client mirrors the
# rows into ONE hidden field (order[line_items]) as a JSON array on every
# add/remove/keystroke. This is for an app whose controller already parses a
# serialized JSON param (JSON.parse(params[:order][:line_items])) — it adopts
# the reactive primitive WITHOUT rewiring its persistence path.
#
# The row markup is authored exactly as in the accepts_nested_attributes_for
# flow: the client infers each JSON key from the trailing bracket segment of a
# row input's name (order[line_items_attributes][3][quantity] → "quantity").
class DraftOrderJsonFormComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  reactive_scope :order

  def view_template
    div(**mix(
      reactive_root(id: "draft_order_json_form", data: { testid: "draft-order-json" })
    )) do
      form(action: "/orders_json", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        label { "Total" }
        input(**reactive_field(:total, type: "number", value: "0", data: { testid: "total" }))

        # The hidden field the client keeps in sync — the single source of truth
        # the server JSON.parses. Seeded "[]" so an empty submit posts an empty
        # array, never a missing param.
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

  # ONE row's markup — authored the same way as the accepts_nested_attributes_for
  # flow. In JSON mode the client reads the key from each name's trailing bracket
  # segment; the per-row names still render (harmless — the controller reads only
  # the JSON field).
  def row_fields(index: nil)
    kwargs = index.nil? ? {} : { index: }
    div(**mix(reactive_nested_row, data: { testid: "item-row" })) do
      input(name: nested_field_name(:line_items, :quantity, **kwargs), type: "number", data: { testid: "qty" })
      input(name: nested_field_name(:line_items, :price, **kwargs), type: "number", data: { testid: "price" })
      button(**mix(reactive_nested_remove, data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
