# frozen_string_literal: true

# Issue #180: value-conditional visibility — reactive_show, the x-show /
# data-show equivalent, via the ONE conditions language (if:/if_any:/unless:).
# A Hash is an AND, an Array is membership, a Range is a threshold, unless:
# negates; the generic controller toggles `hidden` from the fields' CURRENT
# values with NO round trip. reactive_values computes each section's first-paint
# `hidden:` server-side — no per-section mirror method, no flash. Like
# ClientTabsComponent it declares NO actions: no token-bearing trigger anywhere.
class ConditionalFieldsetComponent < Phlex::HTML
  include Phlex::Reactive::Component

  def id = 'conditional-fieldset'

  # First-paint truth: every reactive_show whose fields are all here computes
  # its own initial `hidden:`.
  def reactive_values
    { mode: 'off', gift: false, delivery: 'pickup',
      type: 'individual', country: 'domestic',
      director: false, shareholder: false, role: 'individual', quantity: 1 }
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-4')) do
      shipping_mode
      gift_option
      delivery_choice
      compound_address
      or_of_and_names
      quantity_surcharge
    end
  end

  private

  # A <select> driving a dependent panel: visible WHILE mode != "off".
  def shipping_mode
    div(class: 'flex flex-col gap-2') do
      label(class: 'flex items-center gap-2') do
        span { 'Shipping' }
        select(name: 'mode', class: 'select select-sm w-fit', data: { testid: 'mode' }) do
          option(value: 'off', selected: true) { 'No shipping' }
          option(value: 'standard') { 'Standard' }
          option(value: 'express') { 'Express' }
        end
      end
      # Extra attrs ride THROUGH reactive_show (it deep-merges via mix) — a bare
      # `data:` beside the spread would clobber the binding.
      div(**reactive_show(unless: { mode: 'off' },
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'mode-details' })) do
        'Shipping details — visible while the select is not "No shipping".'
      end
    end
  end

  # A checkbox: its .value is the constant "on", so the binding compares the
  # CHECKED state — `gift: true` is the checkbox form.
  def gift_option
    div(class: 'flex flex-col gap-2') do
      label(class: 'flex items-center gap-2') do
        input(type: 'checkbox', name: 'gift', class: 'checkbox checkbox-sm', data: { testid: 'gift' })
        span { 'This is a gift' }
      end
      div(**reactive_show(if: { gift: true },
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'gift-note' })) do
        'Gift message — visible while the checkbox is checked.'
      end
    end
  end

  # A radio group: the binding reads the CHECKED radio's value.
  def delivery_choice
    div(class: 'flex flex-col gap-2') do
      div(class: 'flex gap-4') do
        label(class: 'flex items-center gap-2') do
          input(type: 'radio', name: 'delivery', value: 'pickup', checked: true,
                class: 'radio radio-sm', data: { testid: 'delivery-pickup' })
          span { 'Pickup' }
        end
        label(class: 'flex items-center gap-2') do
          input(type: 'radio', name: 'delivery', value: 'ship',
                class: 'radio radio-sm', data: { testid: 'delivery-ship' })
          span { 'Ship' }
        end
      end
      div(**reactive_show(if: { delivery: 'ship' },
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'address' })) do
        'Shipping address — visible while the "Ship" radio is checked.'
      end
    end
  end

  # Issue #180: a COMPOUND if:/unless: across TWO fields — one flat binding,
  # visible only while type == "individual" AND country != "domestic".
  def compound_address
    div(class: 'flex flex-col gap-2') do
      div(class: 'flex gap-4') do
        label(class: 'flex items-center gap-2') do
          span { 'Type' }
          select(name: 'type', class: 'select select-sm w-fit', data: { testid: 'type' }) do
            option(value: 'individual', selected: true) { 'Individual' }
            option(value: 'company') { 'Company' }
          end
        end
        label(class: 'flex items-center gap-2') do
          span { 'Country' }
          select(name: 'country', class: 'select select-sm w-fit', data: { testid: 'country' }) do
            option(value: 'domestic', selected: true) { 'Domestic' }
            option(value: 'foreign') { 'Foreign' }
          end
        end
      end
      div(**reactive_show(if: { type: 'individual' }, unless: { country: 'domestic' },
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'intl-address' })) do
        'International address — visible while Individual AND not Domestic.'
      end
    end
  end

  # Issue #180: OR-of-AND (the distributive-law killer) — visible while
  # director OR (shareholder AND role == "individual"). ONE if_any: binding, no
  # nested wrapper divs.
  def or_of_and_names
    div(class: 'flex flex-col gap-2') do
      div(class: 'flex gap-4 items-center') do
        label(class: 'flex items-center gap-2') do
          input(type: 'checkbox', name: 'director', class: 'checkbox checkbox-sm', data: { testid: 'director' })
          span { 'Director' }
        end
        label(class: 'flex items-center gap-2') do
          input(type: 'checkbox', name: 'shareholder', class: 'checkbox checkbox-sm', data: { testid: 'shareholder' })
          span { 'Shareholder' }
        end
        select(name: 'role', class: 'select select-sm w-fit', data: { testid: 'role' }) do
          option(value: 'individual', selected: true) { 'Individual' }
          option(value: 'company') { 'Company' }
        end
      end
      div(**reactive_show(if_any: [{ director: true }, { shareholder: true, role: 'individual' }],
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'name-fields' })) do
        'Name fields — visible while Director OR (Shareholder AND Individual).'
      end
    end
  end

  # Issue #180: a NUMERIC threshold — reveal while quantity >= 10 (a Range).
  def quantity_surcharge
    div(class: 'flex flex-col gap-2') do
      label(class: 'flex items-center gap-2') do
        span { 'Quantity' }
        input(type: 'number', name: 'quantity', value: '1',
              class: 'input input-sm w-24', data: { testid: 'quantity' })
      end
      div(**reactive_show(if: { quantity: 10.. },
                          class: 'rounded-box border border-base-300 p-3',
                          data: { testid: 'surcharge' })) do
        'Bulk surcharge applies — visible while quantity ≥ 10.'
      end
    end
  end
end
