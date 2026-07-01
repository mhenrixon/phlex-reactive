# frozen_string_literal: true

require 'rails_helper'

# The payment-split rebalancer exercises the auto-collected-params contract
# end-to-end: model-scoped bracketed fields nest into the `split:` schema (#67),
# a disabled `total` field is still collected and read (#66), siblings arrive at
# dispatch time (#65), and the action recomputes + morphs without persisting (#64).
RSpec.describe 'Payment split rebalance', type: :request do
  # The bracketed field names the client posts (split[allowance], …). The
  # endpoint bracket-expands these into a nested { "split" => { … } } hash before
  # coercion — mirroring a real Form(model:)-style submission.
  def bracketed(allowance:, cash:, leasing:, total:)
    {
      'changed' => 'allowance',
      'split[allowance]' => allowance.to_s,
      'split[cash]' => cash.to_s,
      'split[leasing]' => leasing.to_s,
      'split[total]' => total.to_s
    }
  end

  let(:state) { { 's' => { 'allowance' => 700, 'cash' => 200, 'leasing' => 100, 'total' => 1000 } } }

  it 'rebalances peers so the three amounts still sum to the total' do
    params = bracketed(allowance: 900, cash: 200, leasing: 100, total: 1000)
    post_action(PaymentSplitComponent, payload: state, act: 'rebalance', params: params)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('target="payment-split"')
    # Edited allowance held at 900; peers spilled to keep the sum at 1000.
    expect(response.body).to include('Balanced')
    expect(response.body).to include('900 + 100 + 0 = 1000')
  end

  it 'reads the DISABLED total field (#66) — a native form would omit it' do
    # Send a different total; the action must honor the collected disabled value.
    params = bracketed(allowance: 400, cash: 200, leasing: 100, total: 800)
    post_action(PaymentSplitComponent, payload: state, act: 'rebalance', params: params)

    expect(response.body).to include('= 800')
  end

  it 'nests the bracketed fields into the split: schema (#67)' do
    # If a flat schema had been used, split would be empty and the amounts would
    # fall back to state (700/200/100). Proving the nested value took effect:
    params = bracketed(allowance: 0, cash: 200, leasing: 100, total: 1000)
    post_action(PaymentSplitComponent, payload: state, act: 'rebalance', params: params)

    expect(response.body).to include('Balanced')
    expect(response.body).not_to include('700 +') # not the fallback state
  end

  it 'morphs in place so the edited field keeps focus (#64 partial update)' do
    params = bracketed(allowance: 700, cash: 200, leasing: 100, total: 1000)
    post_action(PaymentSplitComponent, payload: state, act: 'rebalance', params: params)

    expect(response.body).to include('method="morph"')
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(PaymentSplitComponent, payload: state, act: 'obliterate')
    expect(response).to have_http_status(:forbidden)
  end
end
