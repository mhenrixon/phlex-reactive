# frozen_string_literal: true

# A mini sell-order: a three-way payment split that must sum to `total`. Used by
# the reactive_compute new-vs-persisted example — a new (unsaved) order drives
# the split in-browser (reactive_compute reducer), a persisted order drives it
# server-side through the same PaymentSplit twin.
class Order < ActiveRecord::Base
  def rebalance!(changed:, value:)
    split = PaymentSplit.new(total:, allowance:, cash:, leasing:)
    update!(**split.rebalance(changed:, value:))
  end
end
