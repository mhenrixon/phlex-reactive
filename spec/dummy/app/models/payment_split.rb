# frozen_string_literal: true

# The Ruby twin of the JS payment-split reducer (spec/dummy/public/vendor/
# payment_split_reducer.js). A three-way split — allowance + cash + leasing must
# sum to total. Editing one method rebalances the others: `cash` absorbs the
# remainder unless the edited method exceeds the total, in which case it's capped
# and the peers zero out. This is a condensed stand-in for carlqvist-intracar's
# ::PaymentSplit, kept deliberately identical to the JS so the persisted (server)
# and new-draft (client) paths compute the SAME result — the whole point of
# reactive_compute: one math contract, two execution sites.
class PaymentSplit
  def initialize(total:, allowance:, cash:, leasing:)
    @total = total.to_i
    @allowance = allowance.to_i
    @cash = cash.to_i
    @leasing = leasing.to_i
  end

  # Rebalance after `changed` (:allowance | :cash | :leasing) was edited to
  # `value`. The edited method keeps `value`; the peers absorb the remainder
  # (`cash` first). If the edited method alone exceeds the total, cap it at the
  # total and zero the peers. Returns { allowance:, cash:, leasing: }.
  def rebalance(changed:, value:)
    value = value.to_i
    return capped(changed) if value >= @total

    remainder = @total - value
    zeroed.merge(changed => value, first_peer(changed) => remainder)
  end

  private

  # { allowance: 0, cash: 0, leasing: 0 } with the edited method capped at total.
  def capped(changed)
    zeroed.merge(changed => @total)
  end

  def zeroed
    { allowance: 0, cash: 0, leasing: 0 }
  end

  # The peer that absorbs the remainder for a given edited method: cash absorbs
  # for allowance/leasing edits; allowance absorbs for a cash edit.
  def first_peer(changed)
    changed == :cash ? :allowance : :cash
  end
end
