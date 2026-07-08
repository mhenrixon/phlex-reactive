# frozen_string_literal: true

# The draft nested-attribute rows primitive (issue #208) — a "new order + line
# items" form that builds child rows BEFORE the parent exists. An unsaved
# order has no gid to sign, so this pre-save window can't be a reactive
# collection; instead the rows are pure FORM state (the reactive_tags posture,
# ClientBindings — no token, no actions): reactive_nested_add clones the
# server-owned <template> row client-side (ZERO round trips), and the REAL
# form submit posts order[line_items_attributes][<index>][…] so
# accepts_nested_attributes_for creates the order + rows in ONE request.
#
# The row markup is authored ONCE: `row_fields` renders the template form
# (placeholder index) by default and a server-side row when given a real
# index — the same method would render an edit form's persisted rows.
class DraftOrderFormComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::ClientBindings

  # The parent form's param root: nested_field_name emits
  # order[line_items_attributes][<index>][…] and reactive_field(:total) emits
  # order[total] — the exact names accepts_nested_attributes_for expects.
  reactive_scope :order

  def view_template
    div(**mix(
      # A ClientBindings root has no #id — name it explicitly (the client
      # self-checks for an id at connect).
      reactive_root(id: "draft_order_form", data: { testid: "draft-order" })
    )) do
      # data-turbo must be the STRING "false" — Phlex omits a Ruby `false`
      # attribute entirely, and then Turbo intercepts the POST and drops the
      # 200-HTML response (form responses must redirect under Turbo).
      form(action: "/orders", method: "post", data: { turbo: "false" }) do
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        label { "Total" }
        input(**reactive_field(:total, type: "number", value: "0", data: { testid: "total" }))

        div(**mix(reactive_nested_list(:line_items), data: { testid: "items" }))
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

  # ONE row's markup. The default renders the template prototype (NEW_ROW
  # placeholder names — the client swaps in a fresh index per add); pass a
  # real index to server-render a persisted row with the SAME markup.
  def row_fields(index: nil)
    kwargs = index.nil? ? {} : { index: }
    div(**mix(reactive_nested_row, data: { testid: "item-row" })) do
      input(name: nested_field_name(:line_items, :quantity, **kwargs), type: "number", data: { testid: "qty" })
      input(name: nested_field_name(:line_items, :price, **kwargs), type: "number", data: { testid: "price" })
      button(**mix(reactive_nested_remove, data: { testid: "remove-item" }), aria: { label: "Remove item" }) { "×" }
    end
  end
end
