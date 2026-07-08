# frozen_string_literal: true

# The reactive_compute / new-vs-persisted example — a condensed stand-in for
# carlqvist-intracar's sell-order payment tab.
#
# A three-way payment split (allowance + cash + leasing) must sum to `total`.
# Editing `allowance` rebalances `cash`. The SAME math (PaymentSplit) runs in two
# places depending on whether the order is persisted:
#
#   * NEW (unsaved) order  — state-backed (reactive_state), no GlobalID. The split
#     recomputes IN-BROWSER via reactive_compute (the "payment_split" JS reducer),
#     so a new order feels instant with NO round trip — the classic bespoke-JS
#     calculator, but declared on the component instead of hand-written.
#   * PERSISTED order — record-backed (reactive_record). Editing `allowance` fires
#     a reactive `rebalance` action; the server runs PaymentSplit and streams the
#     recomputed cash back. The database is the source of truth.
#
# Both branches share one Ruby twin (PaymentSplit) and one JS twin
# (payment_split_reducer.js) — the whole point: one contract, two execution sites.
class OrderComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Identity: a persisted order re-finds by GlobalID; a new draft carries its
  # split values as signed state. Declaring BOTH is safe — reactive_token signs
  # gid only when @order is persisted (a new_record has no gid), and the state
  # keys always ride along.
  reactive_record :order
  reactive_state :total, :allowance, :cash, :leasing

  # `mirror:` (issue #159): the new-order page shows a read-only recap OUTSIDE
  # this reactive root (another part of the page); the declared id targets are
  # painted via textContent on every compute pass — cash from the reducer
  # result, total from its field's identity value. No bespoke listener.
  reactive_compute :payment_split,
    inputs: %i[allowance cash leasing total],
    outputs: %i[allowance cash leasing],
    mirror: { cash: "#summary-cash", total: "#summary-total" }

  action :rebalance, params: { allowance: :integer, cash: :integer, leasing: :integer, total: :integer }

  # The order kwarg has a DEFAULT (issue #208): a draft token carries no gid,
  # so from_identity rebuilds through this default — a fresh unsaved Order —
  # and the signed state seeds the split. That's what lets the rebalance
  # action round-trip against a NEW (unsaved) order too, not just recompute
  # in-browser.
  def initialize(order: Order.new, total: nil, allowance: nil, cash: nil, leasing: nil)
    @order = order
    # State values fall back to the record's columns on first render; on a
    # round trip they come from the signed token (new draft) or the DB (persisted).
    @total = total || order.total
    @allowance = allowance || order.allowance
    @cash = cash || order.cash
    @leasing = leasing || order.leasing
  end

  def id = @order.persisted? ? dom_id(@order) : "order-draft"

  # Persisted path: rebalance server-side through the SAME PaymentSplit twin the
  # JS reducer mirrors, then re-render self so cash updates and the token rolls.
  def rebalance(allowance:, cash:, leasing:, total:)
    split = PaymentSplit.new(total:, allowance:, cash:, leasing:)
    result = split.rebalance(changed: :allowance, value: allowance)
    @allowance = result[:allowance]
    @cash = result[:cash]
    @leasing = result[:leasing]
    @total = total
    @order.update!(**result, total:) if @order.persisted?
    reply.replace
  end

  def view_template
    div(**root_attrs) do
      field(:total, @total, testid: "total", readonly: true)
      # The one editable field. On a NEW order it triggers the client reducer
      # (input->reactive#recompute, no network). On a PERSISTED order it fires the
      # reactive rebalance action (change->reactive#dispatch) so the server
      # reconciles. allowance_wiring picks the wiring.
      field(:allowance, @allowance, testid: "allowance", extra: allowance_wiring)
      field(:cash, @cash, testid: "cash", readonly: true)
      field(:leasing, @leasing, testid: "leasing", readonly: true)
    end
  end

  private

  # The reactive root. On a new draft it binds the client compute AT THE ROOT
  # (issue #183: reactive_root(compute:) emits the descriptors + the recompute
  # delegation, so no field needs per-field wiring). nil = no binding (persisted).
  def root_attrs
    reactive_root(compute: (:payment_split unless @order.persisted?))
  end

  # Trigger attrs for the editable allowance field. A new draft recomputes
  # in-browser via the ROOT's compute binding (issue #183 — no per-field wiring);
  # a persisted order round-trips the rebalance action on `change` (server
  # reconciles). Returns a full attrs hash (empty for the new-draft branch).
  def allowance_wiring
    @order.persisted? ? on(:rebalance, event: "change") : {}
  end

  # `extra` is a full attrs hash (its own data:/type:) mixed onto the field so a
  # nested data: never double-wraps into data-data-*.
  def field(name, value, testid:, readonly: false, extra: {})
    label { name.to_s.capitalize }
    attrs = mix(reactive_field(name, value:, type: "number", data: { testid: }), extra)
    attrs[:readonly] = true if readonly
    input(**attrs)
  end
end
