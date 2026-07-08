# frozen_string_literal: true

require "rails_helper"

# APM.attach! (issue #207) — the engine calls this once in after_initialize when
# Phlex::Reactive.apm is set. It resolves the adapter (capability probe), installs
# the ASN subscriber, holds the adapter for the error seam, and no-ops+warns when
# the SDK is absent.
RSpec.describe Phlex::Reactive::APM, ".attach!" do
  around do
    it.run
  ensure
    described_class.reset!
    Phlex::Reactive.remove_instance_variable(:@apm) if Phlex::Reactive.instance_variable_defined?(:@apm)
  end

  let(:adapter) { instance_double(Phlex::Reactive::APM::Adapter, record_action: nil, record_error: nil) }

  # Fire one action.phlex_reactive event (the block is the instrumented work — a
  # no-op here; we assert what the subscriber forwarded, not the block's result).
  def fire_action_event
    Phlex::Reactive.instrument("action", { component: "C", action: "a", outcome: :ok }) { :done }
  end

  it "installs the subscriber and holds the adapter when apm resolves" do
    Phlex::Reactive.apm = adapter
    returned = described_class.attach!

    expect(returned).to be(adapter)
    expect(Phlex::Reactive::APM::Subscriber).to be_installed
    expect(Phlex::Reactive.resolved_apm_adapter).to be(adapter)
  end

  it "routes a live action event to the resolved adapter after attach" do
    Phlex::Reactive.apm = adapter
    described_class.attach!

    fire_action_event

    expect(adapter).to have_received(:record_action)
      .with(hash_including(component: "C", action: "a"), kind_of(Numeric))
  end

  it "no-ops and warns when a Symbol's SDK is absent" do
    Phlex::Reactive.apm = :datadog
    expect(Rails.logger).to receive(:warn).with(a_string_including("apm = :datadog", "not loaded"))

    expect(described_class.attach!).to be_nil
    expect(Phlex::Reactive::APM::Subscriber).not_to be_installed
    expect(Phlex::Reactive.resolved_apm_adapter).to be_nil
  end

  it "is idempotent for the same adapter (no double subscription)" do
    Phlex::Reactive.apm = adapter
    described_class.attach!
    described_class.attach!

    fire_action_event
    expect(adapter).to have_received(:record_action).once
  end

  it "resolves a built-in Symbol to a STABLE instance so attach! stays idempotent" do
    # A Symbol-backed APM used to get a fresh klass.new per detect/attach! call,
    # which broke Subscriber's identity-based idempotency (double subscription).
    allow(Phlex::Reactive::APM::Appsignal).to receive(:available?).and_return(true)
    Phlex::Reactive.apm = :appsignal

    first = described_class.detect(:appsignal)
    second = described_class.detect(:appsignal)
    expect(second).to be(first) # same object across calls

    described_class.attach!
    described_class.attach!
    expect(Phlex::Reactive::APM::Subscriber).to be_installed
    # One record_action per event despite two attach! calls (single subscription).
    allow(first).to receive(:record_action)
    fire_action_event
    expect(first).to have_received(:record_action).once
  end

  it "reset! removes the subscriber and clears the held adapter" do
    Phlex::Reactive.apm = adapter
    described_class.attach!
    described_class.reset!

    expect(Phlex::Reactive::APM::Subscriber).not_to be_installed
    expect(Phlex::Reactive.resolved_apm_adapter).to be_nil
  end
end
