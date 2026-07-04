# frozen_string_literal: true

# Issue #161: value-conditional visibility — reactive_show, the x-show /
# data-show equivalent. Each dependent section declares which field controls
# it plus one literal predicate, and the generic controller toggles `hidden`
# from the field's CURRENT value with NO round trip. Like ClientTabsComponent
# it deliberately declares NO actions: there is no token-bearing trigger
# anywhere, and the system spec's fetch spy proves nothing is ever posted.
# Every section renders its initial `hidden:` from the same server state that
# renders its field, so first paint needs no client reconcile (no flash).
class ConditionalFieldsetComponent < ApplicationComponent
  include Phlex::Reactive::Component

  def id = "conditional-fieldset"

  def view_template
    div(**reactive_root) do
      shipping_mode
      gift_option
      delivery_choice
    end
  end

  private

  # A <select> driving a dependent panel: visible WHILE mode != "off".
  def shipping_mode
    select(name: "mode", data: { testid: "mode" }) do
      option(value: "off", selected: true) { "No shipping" }
      option(value: "standard") { "Standard" }
      option(value: "express") { "Express" }
    end
    # Extra attrs ride THROUGH reactive_show (it deep-merges via mix) — a bare
    # `data:` beside the spread would clobber the binding (Never-Do #8).
    div(**reactive_show(:mode, not: "off", hidden: true, data: { testid: "mode-details" })) do
      "Shipping details"
    end
  end

  # A checkbox: its .value is the constant "on", so the binding compares the
  # CHECKED state — equals: true is the checkbox form.
  def gift_option
    input(type: "checkbox", name: "gift", data: { testid: "gift" })
    div(**reactive_show(:gift, equals: true, hidden: true, data: { testid: "gift-note" })) do
      "Gift message"
    end
  end

  # A radio group: the binding reads the CHECKED radio's value.
  def delivery_choice
    label do
      input(type: "radio", name: "delivery", value: "pickup", checked: true, data: { testid: "delivery-pickup" })
      plain "Pickup"
    end
    label do
      input(type: "radio", name: "delivery", value: "ship", data: { testid: "delivery-ship" })
      plain "Ship"
    end
    div(**reactive_show(:delivery, equals: "ship", hidden: true, data: { testid: "address" })) do
      "Shipping address"
    end
  end
end
