# frozen_string_literal: true

# Issue #180 Phase A: value-conditional visibility via the ONE conditions
# language. Each dependent section declares an if:/if_any:/unless: condition (a
# Hash is an AND, an Array is membership, a Range is a threshold, unless:
# negates); the generic controller toggles `hidden` from the fields' CURRENT
# values with NO round trip. reactive_values computes the first-paint hidden:
# server-side, so no section hand-mirrors its predicate. Like ClientTabsComponent
# it declares NO actions: the system spec's fetch spy proves nothing is posted.
class ConditionalFieldsetComponent < ApplicationComponent
  include Phlex::Reactive::Component

  def id = "conditional-fieldset"

  # First-paint truth (issue #180): every reactive_show whose fields are all
  # here computes its own initial hidden:. No per-section mirror method.
  def reactive_values
    { mode: "off", gift: false, delivery: "pickup",
      type: "individual", country: "domestic",
      director: false, shareholder: false, role: "individual", quantity: 1 }
  end

  def view_template
    # Cross-root show targets (issue #164/#180): the mode select ALSO drives a
    # badge OUTSIDE this root (rendered after the component), via a where-style
    # value — visible while mode is standard OR express (a membership Array,
    # positive form of "not off"). The MULTI-FIELD target (issue #209) shares
    # the ONE call (mix would space-join a second call's JSON): the outside
    # bulk alert reads TWO owned fields — company AND quantity >= 10 — via a
    # target-keyed conditions Hash, the exact shape a bespoke JS listener used
    # to be the only way to express.
    div(**mix(reactive_root,
      reactive_show_targets(
        mode: { "#cf-mode-badge" => %w[standard express] },
        "#cf-bulk-alert" => { if: { type: "company", quantity: 10.. } }
      ))) do
      shipping_mode
      gift_option
      delivery_choice
      compound_address
      or_of_and_names
      quantity_surcharge
    end
  end

  private

  # A <select> driving a dependent panel: visible WHILE mode != "off" (unless:).
  def shipping_mode
    select(name: "mode", data: { testid: "mode" }) do
      option(value: "off", selected: true) { "No shipping" }
      option(value: "standard") { "Standard" }
      option(value: "express") { "Express" }
    end
    div(**reactive_show(unless: { mode: "off" }, data: { testid: "mode-details" })) do
      "Shipping details"
    end
  end

  # A checkbox: its .value is the constant "on", so the condition compares the
  # CHECKED state — gift: true is the checkbox form.
  def gift_option
    input(type: "checkbox", name: "gift", data: { testid: "gift" })
    div(**reactive_show(if: { gift: true }, data: { testid: "gift-note" })) do
      "Gift message"
    end
  end

  # A radio group: the condition reads the CHECKED radio's value.
  def delivery_choice
    label do
      input(type: "radio", name: "delivery", value: "pickup", checked: true, data: { testid: "delivery-pickup" })
      plain "Pickup"
    end
    label do
      input(type: "radio", name: "delivery", value: "ship", data: { testid: "delivery-ship" })
      plain "Ship"
    end
    div(**reactive_show(if: { delivery: "ship" }, data: { testid: "address" })) do
      "Shipping address"
    end
  end

  # Compound AND across TWO fields (issue #180): visible while type ==
  # "individual" AND country != "domestic" — one flat if:/unless: binding, no
  # wrapper-div nesting.
  def compound_address
    select(name: "type", data: { testid: "type" }) do
      option(value: "individual", selected: true) { "Individual" }
      option(value: "company") { "Company" }
    end
    select(name: "country", data: { testid: "country" }) do
      option(value: "domestic", selected: true) { "Domestic" }
      option(value: "foreign") { "Foreign" }
    end
    div(**reactive_show(if: { type: "individual" }, unless: { country: "domestic" },
      data: { testid: "intl-address" })) do
      "International address"
    end
  end

  # OR-of-AND (issue #180 — the distributive-law killer): visible while
  # director OR (shareholder AND role == "individual"). ONE if_any: binding,
  # no nested wrapper divs, no hand-applied distributive law. This is the exact
  # shape a production adopter had to decompose by hand — now a permanent
  # regression test.
  def or_of_and_names
    label do
      input(type: "checkbox", name: "director", data: { testid: "director" })
      plain "Director"
    end
    label do
      input(type: "checkbox", name: "shareholder", data: { testid: "shareholder" })
      plain "Shareholder"
    end
    select(name: "role", data: { testid: "role" }) do
      option(value: "individual", selected: true) { "Individual" }
      option(value: "company") { "Company" }
    end
    div(**reactive_show(if_any: [
      { director: true },
      { shareholder: true, role: "individual" }
    ], data: { testid: "name-fields" })) do
      "Name fields"
    end
  end

  # Numeric threshold (issue #180): reveal while quantity >= 10 (a Range). With
  # disable: true, the surcharge's own control is disabled while hidden so a
  # stale value never submits.
  def quantity_surcharge
    input(type: "number", name: "quantity", value: "1", data: { testid: "quantity" })
    div(**reactive_show(if: { quantity: 10.. }, disable: true, data: { testid: "surcharge" })) do
      plain "Bulk surcharge applies — confirm:"
      input(type: "text", name: "bulk_ack", value: "1", data: { testid: "bulk-ack" })
    end
  end
end
