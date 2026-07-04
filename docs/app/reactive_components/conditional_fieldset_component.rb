# frozen_string_literal: true

# Issue #161: value-conditional visibility — reactive_show, the x-show /
# data-show equivalent. Each dependent section declares which field controls it
# plus ONE literal predicate, and the generic controller toggles `hidden` from
# the field's CURRENT value with NO round trip. Like ClientTabsComponent it
# declares NO actions: there is no token-bearing trigger anywhere. Every section
# renders its initial `hidden:` from the same server state that renders its
# field, so first paint needs no client reconcile (no flash).
class ConditionalFieldsetComponent < Phlex::HTML
  include Phlex::Reactive::Component

  def id = 'conditional-fieldset'

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-4')) do
      shipping_mode
      gift_option
      delivery_choice
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
      div(**reactive_show(:mode, not: 'off', hidden: true,
                                 class: 'rounded-box border border-base-300 p-3',
                                 data: { testid: 'mode-details' })) do
        'Shipping details — visible while the select is not "No shipping".'
      end
    end
  end

  # A checkbox: its .value is the constant "on", so the binding compares the
  # CHECKED state — equals: true is the checkbox form.
  def gift_option
    div(class: 'flex flex-col gap-2') do
      label(class: 'flex items-center gap-2') do
        input(type: 'checkbox', name: 'gift', class: 'checkbox checkbox-sm', data: { testid: 'gift' })
        span { 'This is a gift' }
      end
      div(**reactive_show(:gift, equals: true, hidden: true,
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
      div(**reactive_show(:delivery, equals: 'ship', hidden: true,
                                     class: 'rounded-box border border-base-300 p-3',
                                     data: { testid: 'address' })) do
        'Shipping address — visible while the "Ship" radio is checked.'
      end
    end
  end
end
