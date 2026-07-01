# frozen_string_literal: true

require "rails_helper"

# The shared Ruby twin of the JS payment-split reducer. Locking it here keeps the
# two execution sites (server rebalance action + client reactive_compute) in
# lockstep — a divergence would mean a new draft and a saved order compute
# different splits, the exact bug reactive_compute exists to prevent.
RSpec.describe PaymentSplit do
  subject(:split) { described_class.new(total: 500, allowance: 0, cash: 500, leasing: 0) }

  it "cash absorbs the remainder when allowance is edited" do
    expect(split.rebalance(changed: :allowance, value: 100)).to eq(allowance: 100, cash: 400, leasing: 0)
  end

  it "allowance absorbs the remainder when cash is edited" do
    expect(split.rebalance(changed: :cash, value: 200)).to eq(allowance: 300, cash: 200, leasing: 0)
  end

  it "caps the edited method at total and zeros the peers when it exceeds total" do
    expect(split.rebalance(changed: :allowance, value: 999)).to eq(allowance: 500, cash: 0, leasing: 0)
  end

  it "caps exactly at total (== total edits to a full cap, peers zero)" do
    expect(split.rebalance(changed: :leasing, value: 500)).to eq(allowance: 0, cash: 0, leasing: 500)
  end
end
