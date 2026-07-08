# frozen_string_literal: true

# A mini sell-order: a three-way payment split that must sum to `total`. Used by
# the reactive_compute new-vs-persisted example — a new (unsaved) order drives
# the split in-browser (reactive_compute reducer), a persisted order drives it
# server-side through the same PaymentSplit twin.
class Order < ActiveRecord::Base
  # Issue #208: the draft-order form posts order + line items in ONE request —
  # the reconcile half of the client-side nested-rows primitive.
  has_many :line_items, dependent: :destroy
  accepts_nested_attributes_for :line_items, allow_destroy: true

  def rebalance!(changed:, value:)
    split = PaymentSplit.new(total:, allowance:, cash:, leasing:)
    update!(**split.rebalance(changed:, value:))
  end
end
