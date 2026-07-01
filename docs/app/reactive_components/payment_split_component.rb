# frozen_string_literal: true

# A live "sum-to-total" split calculator — the pattern behind issues #64–#67.
# Three amounts (allowance / cash / leasing) must always add up to a fixed
# `total`. Editing one field rebalances the OTHER two server-side (spill the
# difference into the largest peer, clamped at zero), and the component
# re-renders in place so every field shows the reconciled number.
#
# It is STATE-backed (no DB): the three amounts + the total ride in the signed
# token, and each rebalance is pure computation over the values the client
# collected from the form — nothing is persisted, nothing is broadcast. In a
# real app you would swap `reactive_state` for `reactive_record :invoice` and
# authorize the row (identity + auth only), keeping the same "compute over the
# live fields, don't persist" shape — see the README "Record-authorized,
# transient-state actions" section.
#
# What each issue maps to, made concrete:
#   #67  the fields are named `split[allowance]`, … (model-scoped brackets), so
#        the action schema NESTS under `split:` to match — a flat schema would
#        silently collect nothing.
#   #65  editing one field fires `rebalance` with the CURRENT value of every
#        sibling (read at dispatch time), so the server sees the whole form.
#   #66  `total` is a DISABLED display field, yet it is still collected and read
#        by the action (deliberately unlike a native form submit).
#   #64  the record (here: state) is authority for the numbers; the action
#        recomputes and re-renders without persisting or broadcasting.
class PaymentSplitComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  FIELDS = %i[allowance cash leasing].freeze

  # All three amounts + the total are signed into the identity token.
  reactive_state :allowance, :cash, :leasing, :total

  # ONE nested schema, reused by all three triggers. The inputs are named
  # `split[allowance]`, `split[cash]`, `split[leasing]`, `split[total]`, so the
  # schema nests under `split:` to match the bracket-expanded params (#67). A
  # `changed` scalar param rides alongside to say WHICH field the user edited.
  SPLIT_PARAMS = {
    changed: :string,
    split: { allowance: :integer, cash: :integer, leasing: :integer, total: :integer }
  }.freeze

  action :rebalance, params: SPLIT_PARAMS

  def initialize(allowance: 700, cash: 200, leasing: 100, total: 1000)
    @allowance = allowance.to_i
    @cash      = cash.to_i
    @leasing   = leasing.to_i
    @total     = total.to_i
  end

  def id = 'payment-split'

  # The client collected every named field of this root — including the DISABLED
  # `total` (#66) — and bracket-expanded them into `split:` (#67). `changed`
  # names the edited field. We recompute over those live values (#65), assign the
  # reconciled amounts, and morph in place so the edited field keeps its caret
  # and the peers show their new numbers. No persist, no broadcast (#64).
  def rebalance(changed:, split:)
    edited = changed.to_sym
    edited = :allowance unless FIELDS.include?(edited)

    apply(split)
    reconcile(edited)
    reply.morph
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-3', data: { testid: 'payment-split' })) do
      p(class: 'text-sm opacity-70') do
        plain 'Editing one amount rebalances the others so they always sum to the total.'
      end
      FIELDS.each { amount_row(it) }
      total_row
      remainder_note
    end
  end

  private

  # Coerce the collected split hash back onto our state. Missing keys keep their
  # current value (defensive — the schema drops anything undeclared already).
  def apply(split)
    @allowance = int(split[:allowance], @allowance)
    @cash      = int(split[:cash], @cash)
    @leasing   = int(split[:leasing], @leasing)
    @total     = int(split[:total], @total)
  end

  def int(value, fallback)
    value.nil? ? fallback : value.to_i
  end

  # Fold the whole difference back into the peers so the three amounts sum to
  # `total`. Clamp the edited field into [0, total], then spill the remainder
  # across the other two (largest first), never below zero.
  def reconcile(edited)
    set(edited, current(edited).clamp(0, @total))
    remainder = @total - current(edited)

    peers = (FIELDS - [edited]).sort_by { |f| -current(f) }
    peers.each_with_index do |field, index|
      share = index == peers.size - 1 ? remainder : [current(field), remainder].min
      share = share.clamp(0, remainder)
      set(field, share)
      remainder -= share
    end
  end

  def current(field) = instance_variable_get(:"@#{field}")
  def set(field, value) = instance_variable_set(:"@#{field}", value)

  def sum = FIELDS.sum { current(it) }

  def amount_row(field)
    label(class: 'flex items-center justify-between gap-3') do
      span(class: 'w-28 capitalize') { field.to_s }
      # A change-triggered rebalance carrying `changed:` so the server knows which
      # field the user edited. The field NAME is bracketed (`split[allowance]`) so
      # it bracket-expands into the nested `split:` schema (#67). mix() keeps
      # on()'s data-action from being clobbered by our name/value/class.
      input(**mix(
        on(:rebalance, event: 'change', changed: field.to_s),
        type: 'number',
        name: "split[#{field}]",
        value: current(field),
        min: 0,
        class: 'input input-bordered input-sm w-32 text-right tabular-nums',
        data: { testid: "split-#{field}" }
      ))
    end
  end

  # The total is a DISABLED, computed display field. It is still a named control
  # of the reactive root, so the client collects it and the action reads it (#66)
  # — a native <form> submit would omit it. It's disabled because the user edits
  # the amounts, not the target.
  def total_row
    label(class: 'flex items-center justify-between gap-3 border-t border-base-300 pt-2') do
      span(class: 'w-28 font-semibold') { 'Total' }
      input(
        type: 'number',
        name: 'split[total]',
        value: @total,
        disabled: true,
        class: 'input input-bordered input-sm w-32 text-right font-semibold tabular-nums',
        data: { testid: 'split-total' }
      )
    end
  end

  # A tiny live proof the invariant holds after every rebalance.
  def remainder_note
    balanced = sum == @total
    div(class: ['text-sm', (balanced ? 'text-success' : 'text-error')],
        data: { testid: 'split-remainder' }) do
      plain(balanced ? "Balanced — #{@allowance} + #{@cash} + #{@leasing} = #{@total}" : "Off by #{@total - sum}")
    end
  end
end
