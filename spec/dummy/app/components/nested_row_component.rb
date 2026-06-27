# frozen_string_literal: true

# A nested reactive root rendered INSIDE NestedEditorComponent (issue #15). It
# owns a bare-named `quantity` input — the same name shape the cosmos line-item
# rows used. An action on the OUTER editor must NOT collect this field.
class NestedRowComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :label, :quantity
  action :update, params: {quantity: :string}

  def initialize(label:, quantity: "1")
    @label = label
    @quantity = quantity
  end

  def id = "row-#{@label}"

  def update(quantity:)
    @quantity = quantity
  end

  def view_template
    div(**mix(reactive_attrs, id:, data: {testid: "row"})) do
      input(**mix(on(:update, event: "change"), name: "quantity", value: @quantity, data: {testid: "row-qty-#{@label}"}))
      span(data: {testid: "row-echo-#{@label}"}) { @quantity }
    end
  end
end
